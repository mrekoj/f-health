import Foundation
import SwiftData

/// Gom số liệu (nguồn Apple/Google + nhật ký SwiftData) thành `HealthReport` cho 1 kỳ, rồi chạy
/// **nhận xét tự động theo ngưỡng cá nhân** (không cần AI). Gói này cũng là thứ gửi AI ở T-026.
@MainActor
enum HealthReportBuilder {

    static func build(period: ReportPeriod,
                      provider: any HealthStoreProvider,
                      source: HealthSource,
                      context: ModelContext,
                      profile: HealthProfile = HealthProfileStore.current,
                      now: Date = Date()) async -> HealthReport {
        let cal = Calendar.current
        let from = period.previousStart
        let to = period.end
        let currentDates = ReportMath.days(from: period.start, to: period.end)
        let previousDates = ReportMath.days(from: period.previousStart, to: period.previousEnd)

        // 1) Chuỗi theo ngày từ nguồn — lỗi từng chuỗi thì bỏ qua (báo cáo vẫn ra với phần còn lại).
        async let sleepS = (try? await provider.sleepSummaries(from: from, to: to)) ?? []
        async let rhrS = (try? await provider.restingHeartRates(from: from, to: to)) ?? []
        async let stepsS = (try? await provider.stepsSeries(from: from, to: to)) ?? []
        async let weightS = (try? await provider.bodyMasses(from: from, to: to)) ?? []
        async let hrvS = source.usesGoogle ? ((try? await provider.heartRateVariabilities(from: from, to: to)) ?? []) : []
        async let skinS = source.usesGoogle ? ((try? await provider.skinTemperatures(from: from, to: to)) ?? []) : []
        // Chỉ kỳ hiện tại (mỗi ngày 1 lượt gọi) — đủ cho nhận xét, không làm Google quá tải.
        // 90 ngày: bỏ 3 chuỗi phải gọi từng ngày (quãng đường/giờ vận động/dải nhịp tim) để không gọi Google ~270 lượt.
        let heavy = period.kind != .quarter
        async let distS = heavy ? ((try? await provider.distanceSeries(from: period.start, to: to)) ?? []) : []
        async let activeS = heavy ? ((try? await provider.activeHoursSeries(from: period.start, to: to)) ?? []) : []
        async let rangeS = heavy ? ((try? await provider.heartRateDailyRanges(from: period.start, to: to)) ?? []) : []

        var byDate: [Date: ReportDay] = [:]
        func day(_ d: Date) -> ReportDay { byDate[cal.startOfDay(for: d)] ?? ReportDay(date: cal.startOfDay(for: d)) }
        func put(_ r: ReportDay) { byDate[r.date] = r }

        for (d, s) in await sleepS {
            var r = day(d); r.sleepHours = s.totalHours; r.bedTime = s.bedTime; r.wakeTime = s.wakeTime
            r.awakeCount = s.awakeCount; put(r)
        }
        for (d, v) in await rhrS { var r = day(d); r.restingHR = v; put(r) }
        for (d, v) in await stepsS { var r = day(d); r.steps = v; put(r) }
        for (d, v) in await weightS { var r = day(d); r.weightKg = v; put(r) }
        for (d, v) in await hrvS { var r = day(d); r.hrv = v; put(r) }
        for (d, v) in await skinS { var r = day(d); r.skinTemp = v; put(r) }
        for (d, v) in await distS { var r = day(d); r.distanceKm = v; put(r) }
        for (d, v) in await activeS { var r = day(d); r.activeHours = v; put(r) }
        for (d, lo, hi, _) in await rangeS where hi > lo { var r = day(d); r.heartMin = lo; r.heartMax = hi; put(r) }

        // Kỳ ngắn (≤ 7 ngày): nhịp thở / oxy máu + giai đoạn ngủ + nhịp tim theo giờ từng ngày (T-030).
        // Kỳ dài để AI tự hỏi qua công cụ (đỡ gọi Google hàng trăm lượt).
        if period.kind.loadsDetail {
            for d in currentDates {
                let br = (try? await provider.respiratoryRate(for: d)) ?? nil
                let ox = (try? await provider.oxygenSaturation(for: d)) ?? nil
                var r = day(d)
                r.respiratoryRate = br; r.oxygen = ox
                if let detail = (try? await provider.sleepDetail(for: d)) ?? nil, !detail.segments.isEmpty {
                    Self.fill(&r, with: detail)
                }
                if let pts = (try? await provider.intradayHeartRate(for: d)) ?? nil, !pts.isEmpty {
                    r.hourlyHR = Self.hourly(pts)
                }
                put(r)
            }
        }

        // 2) Nhật ký ghi tay + tự động (SwiftData) trong [from, to + 1 ngày).
        let fetchEnd = cal.date(byAdding: .day, value: 1, to: to) ?? to
        let entries = (try? context.fetch(FetchDescriptor<LogEntry>(
            predicate: #Predicate { $0.timestamp >= from && $0.timestamp < fetchEnd }))) ?? []
        for e in entries {
            var r = day(e.timestamp)
            switch e.kind {
            case .alcohol:
                r.alcoholUnits += e.amount ?? 1
                if r.alcoholLatest.map({ e.timestamp > $0 }) ?? true { r.alcoholLatest = e.timestamp }
            case .meal:
                r.meals.append("\(TodayViewModel.time(e.timestamp)) " + [e.title, e.detail].compactMap { $0 }.joined(separator: ": "))
                let m = MealPlan.minuteOfDay(e.timestamp)
                r.lastMealMinute = max(r.lastMealMinute ?? 0, m)
            case .symptom:
                r.symptoms.append(contentsOf: (e.detail ?? e.title).split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces) })
                r.symptomTimes.append(TodayViewModel.time(e.timestamp))
            case .weight:
                if let kg = e.amount { r.weightKg = kg }
            }
            put(r)
        }
        let naps = (try? context.fetch(FetchDescriptor<NapLog>(
            predicate: #Predicate { $0.start >= from && $0.start < fetchEnd }))) ?? []
        for n in naps {
            var r = day(n.start)
            r.napCount += 1; r.napMinutes += n.minutes
            if cal.component(.hour, from: n.start) >= 15 { r.napLateCount += 1 }
            put(r)
        }
        let sessions = (try? context.fetch(FetchDescriptor<LiveSession>(
            predicate: #Predicate { $0.start >= from && $0.start < fetchEnd }))) ?? []
        for s in sessions where s.isBreathing {
            var r = day(s.start)
            r.breathingSessions += 1
            if let a = s.startBpm, let b = s.endBpm { r.breathingDrops.append(a - b) }
            put(r)
        }
        let events = (try? context.fetch(FetchDescriptor<HeartEvent>(
            predicate: #Predicate { $0.time >= from && $0.time < fetchEnd }))) ?? []
        for e in events {
            var r = day(e.time)
            let bpm = e.bpm.map { " (\(Int($0.rounded())) lần/phút)" } ?? ""
            r.heartEvents.append("\(TodayViewModel.time(e.time)) \(e.note)\(bpm)")
            put(r)
        }

        let days = currentDates.map { day($0) }
        let previous = previousDates.map { day($0) }
        

        // 3) Tổng hợp + nhận xét.
        let analysis = ReportAnalyzer(period: period, days: days, previous: previous, profile: profile, now: now)
        let stats = analysis.stats()
        let findings = analysis.findings()
        let (level, text) = analysis.overall(findings: findings)
        let advice = analysis.advice(from: findings)

        return HealthReport(period: period, generatedAt: now, profile: profile,
                            sourceTitle: source.title, isMock: HealthStoreFactory.useMock,
                            days: days, previousDays: previous,
                            stats: stats, findings: findings, advice: advice,
                            overallLevel: level, overallText: text)
    }
}

extension HealthReportBuilder {
    /// Đổ giai đoạn ngủ + các lần thức vào dòng ngày.
    nonisolated static func fill(_ r: inout ReportDay, with d: SleepDetail) {
        r.deepMinutes = d.minutes(of: .deep)
        r.remMinutes = d.minutes(of: .rem)
        r.lightMinutes = d.minutes(of: .light)
        r.awakeMinutes = d.awakeMinutes
        r.latencyMinutes = d.latencyMinutes
        r.awakeEpisodes = d.awakeEpisodes.filter { $0.minutes >= 5 }
            .map { "\(TodayViewModel.time($0.start)) (\(Int($0.minutes.rounded()))')" }
        // Ưu tiên số từ giai đoạn ngủ (khớp màn Giấc ngủ chi tiết — đã lấp khoảng thức giữa đêm).
        if d.asleepHours > 0 { r.sleepHours = d.asleepHours; r.bedTime = d.bedTime; r.wakeTime = d.wakeTime; r.awakeCount = d.awakeCount }
    }

    /// Gom nhịp tim theo giờ: thấp / TB / cao mỗi giờ có số.
    nonisolated static func hourly(_ pts: [(time: Date, bpm: Double)]) -> [(hour: Int, lo: Int, avg: Int, hi: Int)] {
        var b: [Int: [Double]] = [:]
        for p in pts { b[Calendar.current.component(.hour, from: p.time), default: []].append(p.bpm) }
        return b.keys.sorted().map { h in
            let v = b[h]!
            return (h, Int(v.min()!.rounded()), Int((v.reduce(0, +) / Double(v.count)).rounded()), Int(v.max()!.rounded()))
        }
    }
}

// MARK: - Nhận xét tự động theo ngưỡng cá nhân

/// Quy tắc đời thường, không phải chẩn đoán. Mỗi nhận xét có mức xanh/vàng/đỏ + việc nên làm.
struct ReportAnalyzer {
    let period: ReportPeriod
    let days: [ReportDay]
    let previous: [ReportDay]
    let profile: HealthProfile
    let now: Date

    private var you: String { profile.addressAs }
    private var isDay: Bool { period.kind == .day }
    private var n: Int { days.count }

    private func dec(_ v: Double, _ d: Int = 1) -> String { TodayViewModel.decimal(v, digits: d) }
    private func grp(_ v: Int) -> String { TodayViewModel.grouped(v) }

    // Trung bình các chuỗi
    private var sleepAvg: Double? { ReportMath.mean(days.compactMap(\.sleepHours)) }
    private var prevSleepAvg: Double? { ReportMath.mean(previous.compactMap(\.sleepHours)) }
    private var rhrAvg: Double? { ReportMath.mean(days.compactMap(\.restingHR)) }
    private var prevRhrAvg: Double? { ReportMath.mean(previous.compactMap(\.restingHR)) }
    private var hrvAvg: Double? { ReportMath.mean(days.compactMap(\.hrv)) }
    private var prevHrvAvg: Double? { ReportMath.mean(previous.compactMap(\.hrv)) }
    private var stepsAvg: Double? { ReportMath.mean(days.compactMap { $0.steps.map(Double.init) }) }
    private var prevStepsAvg: Double? { ReportMath.mean(previous.compactMap { $0.steps.map(Double.init) }) }
    private var weights: [(Date, Double)] { days.compactMap { d in d.weightKg.map { (d.date, $0) } } }
    private var prevWeights: [(Date, Double)] { previous.compactMap { d in d.weightKg.map { (d.date, $0) } } }
    private var alcoholDays: [ReportDay] { days.filter(\.hadAlcohol) }
    private var alcoholUnits: Double { days.reduce(0) { $0 + $1.alcoholUnits } }
    private var symptomCounts: [(String, Int)] {
        var c: [String: Int] = [:]
        for d in days { for s in d.symptoms where !s.isEmpty { c[s, default: 0] += 1 } }
        return c.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    // MARK: Ô số

    func stats() -> [ReportStat] {
        var out: [ReportStat] = []
        let per = isDay ? "so TB 7 ngày trước" : "so kỳ trước"

        if let s = sleepAvg {
            out.append(ReportStat(id: "sleep", title: isDay ? "Ngủ đêm qua" : "Ngủ trung bình",
                                  value: dec(s), unit: "giờ/đêm", level: Thresholds.sleep(hours: s),
                                  delta: prevSleepAvg.map { ReportMath.deltaText(s - $0, digits: 1, suffix: per) },
                                  symbol: Metric.sleep.symbol))
        }
        if let r = rhrAvg {
            out.append(ReportStat(id: "rhr", title: "Nhịp tim nghỉ", value: "\(Int(r.rounded()))", unit: "lần/phút",
                                  level: Thresholds.restingHeartRate(bpm: r),
                                  delta: prevRhrAvg.map { ReportMath.deltaText(r - $0, digits: 0, suffix: per) },
                                  symbol: Metric.restingHeartRate.symbol))
        }
        if let v = hrvAvg {
            out.append(ReportStat(id: "hrv", title: "Biến thiên nhịp tim", value: "\(Int(v.rounded()))", unit: "ms",
                                  level: Thresholds.heartRateVariability(ms: v),
                                  delta: prevHrvAvg.map { ReportMath.deltaText(v - $0, digits: 0, suffix: per) },
                                  symbol: Metric.heartRateVariability.symbol))
        }
        if let st = stepsAvg {
            out.append(ReportStat(id: "steps", title: isDay ? "Bước chân" : "Bước trung bình", value: grp(Int(st.rounded())),
                                  unit: "bước/ngày", level: Thresholds.steps(Int(st.rounded())),
                                  delta: prevStepsAvg.map { ReportMath.deltaText(st - $0, digits: 0, suffix: per) },
                                  symbol: Metric.steps.symbol))
        }
        if let last = weights.last {
            let delta: String?
            if !isDay, let first = weights.first, first.0 != last.0 {
                delta = ReportMath.deltaText(last.1 - first.1, digits: 1, suffix: "trong kỳ")
            } else if let p = prevWeights.last {
                delta = ReportMath.deltaText(last.1 - p.1, digits: 1, suffix: "so lần trước")
            } else { delta = nil }
            out.append(ReportStat(id: "weight", title: "Cân nặng", value: dec(last.1), unit: "kg",
                                  level: Thresholds.bodyMass(kg: last.1), delta: delta, symbol: Metric.bodyMass.symbol))
        }
        if alcoholUnits > 0 || !isDay {
            let units = Int(alcoholUnits.rounded())
            out.append(ReportStat(id: "alcohol", title: "Rượu bia", value: "\(units)",
                                  unit: isDay ? "ly" : "ly · \(alcoholDays.count) ngày",
                                  level: units == 0 ? .good : (alcoholDays.count <= 1 && units <= 2 ? .caution : .bad),
                                  delta: nil, symbol: LogKind.alcohol.symbol))
        }
        let napTotal = days.reduce(0) { $0 + $1.napCount }
        if napTotal > 0 {
            let mins = days.reduce(0) { $0 + $1.napMinutes }
            out.append(ReportStat(id: "nap", title: "Ngủ trưa", value: "\(napTotal)", unit: "giấc · \(mins) phút",
                                  level: Explanations.napLevel(minutes: mins / max(1, napTotal)), delta: nil,
                                  symbol: "powersleep"))
        }
        let sym = symptomCounts.reduce(0) { $0 + $1.1 }
        if sym > 0 {
            out.append(ReportStat(id: "symptom", title: "Triệu chứng", value: "\(sym)", unit: "lần ghi",
                                  level: sym >= 3 ? .bad : .caution, delta: nil, symbol: LogKind.symptom.symbol))
        }
        if let o = ReportMath.mean(days.compactMap(\.oxygen)) {
            out.append(ReportStat(id: "oxygen", title: "Oxy máu", value: "\(Int(o.rounded()))", unit: "%",
                                  level: Thresholds.oxygenSaturation(o), delta: nil, symbol: Metric.oxygenSaturation.symbol))
        }
        let breaths = days.reduce(0) { $0 + $1.breathingSessions }
        if breaths > 0 {
            let drops = days.flatMap(\.breathingDrops)
            let avgDrop = ReportMath.mean(drops.map(Double.init))
            out.append(ReportStat(id: "breath", title: "Bài thở", value: "\(breaths)",
                                  unit: avgDrop.map { "lần · hạ ~\(Int($0.rounded())) nhịp" } ?? "lần",
                                  level: .good, delta: nil, symbol: "wind"))
        }
        return out
    }

    // MARK: Nhận xét

    func findings() -> [ReportFinding] {
        var out: [ReportFinding] = []
        let goal = Thresholds.sleepGoalHours
        let goalText = Thresholds.sleepGoalText

        // --- Giấc ngủ: trung bình + số đêm thiếu
        if let s = sleepAvg {
            let level = Thresholds.sleep(hours: s)
            let short = days.filter { ($0.sleepHours ?? 99) < goal - 1 }.count
            let good = days.filter { ($0.sleepHours ?? 0) >= goal }.count
            let detail: String
            if isDay {
                let d = days[0]
                var t = "Đêm qua \(you) ngủ \(dec(s)) giờ"
                if let b = d.bedTime, let w = d.wakeTime { t += " (\(TodayViewModel.time(b)) → \(TodayViewModel.time(w)))" }
                if let a = d.awakeCount, a > 0 { t += ", thức giấc \(a) lần" }
                t += level == .good ? " — đạt mục tiêu \(goalText)." : " — thiếu \(dec(goal - s)) giờ so với mục tiêu \(goalText)."
                detail = t
            } else {
                var t = "Ngủ trung bình \(dec(s)) giờ/đêm; \(good)/\(n) đêm đạt \(goalText)"
                if short > 0 { t += ", \(short) đêm dưới \(dec(goal - 1, 0)) giờ" }
                if let p = prevSleepAvg { t += " (kỳ trước \(dec(p)) giờ)" }
                detail = t + "."
            }
            out.append(ReportFinding(
                id: "sleep-avg", level: level,
                title: level == .good ? "Ngủ đủ giấc" : (level == .caution ? "Ngủ hơi thiếu" : "Ngủ ít"),
                detail: detail,
                advice: level == .good ? nil
                    : "Lên giường trước 23h, tắt máy từ 22h; bù giấc bằng ngủ trưa ngắn 15–20 phút (không sau 15h).",
                isDoctor: profile.doctorNotes.lowercased().contains("ngủ")))
        }

        // --- Giờ đi ngủ đều hay thất thường (chỉ tuần/tháng)
        if !isDay {
            let bed = days.compactMap(\.bedTime).map(ReportMath.bedMinute)
            if bed.count >= 3, let m = ReportMath.mean(bed), let sd = ReportMath.stdev(bed) {
                let late = bed.filter { $0 > 23 * 60 + 30 }.count
                let level: MetricLevel = sd > 75 ? .bad : (sd > 40 ? .caution : .good)
                out.append(ReportFinding(
                    id: "bedtime", level: level,
                    title: level == .good ? "Giờ đi ngủ đều" : "Giờ đi ngủ thất thường",
                    detail: "Đi ngủ trung bình lúc \(ReportMath.minuteText(m)), lệch ± \(Int(sd.rounded())) phút giữa các đêm"
                        + (late > 0 ? "; \(late) đêm ngủ sau 23h30." : "."),
                    advice: level == .good ? nil : "Chọn một giờ đi ngủ cố định (22h30–23h) kể cả cuối tuần — cơ thể ngủ sâu hơn khi giờ giấc đều.",
                    isDoctor: false))
            }
        }

        // --- Rượu bia & tác động lên đêm sau
        if !alcoholDays.isEmpty {
            let units = Int(alcoholUnits.rounded())
            let late = alcoholDays.filter { d in d.alcoholLatest.map { Calendar.current.component(.hour, from: $0) >= 21 } ?? false }.count
            var detail = isDay ? "Hôm nay \(you) uống \(units) ly." : "\(alcoholDays.count) ngày có rượu bia, tổng \(units) ly."
            if late > 0 { detail += " \(late) lần uống sau 21h." }
            // So đêm sau ngày uống với đêm thường (cần ≥ 2 mỗi nhóm).
            if !isDay {
                let cal = Calendar.current
                let after = alcoholDays.compactMap { d -> ReportDay? in
                    guard let next = cal.date(byAdding: .day, value: 1, to: d.date) else { return nil }
                    return days.first { $0.date == next }
                }
                let normal = days.filter { d in
                    guard let prev = cal.date(byAdding: .day, value: -1, to: d.date) else { return false }
                    return !(days.first { $0.date == prev }?.hadAlcohol ?? false)
                }
                if let a = ReportMath.mean(after.compactMap(\.sleepHours)), let b = ReportMath.mean(normal.compactMap(\.sleepHours)),
                   after.count >= 2, normal.count >= 2, b - a >= 0.4 {
                    detail += " Đêm sau khi uống ngủ ít hơn \(dec(b - a)) giờ so với đêm thường."
                }
                if let a = ReportMath.mean(after.compactMap(\.restingHR)), let b = ReportMath.mean(normal.compactMap(\.restingHR)),
                   after.count >= 2, normal.count >= 2, a - b >= 3 {
                    detail += " Nhịp tim nghỉ hôm sau cao hơn \(Int((a - b).rounded())) nhịp."
                }
            }
            let doctorBan = profile.doctorNotes.lowercased().contains("rượu")
            out.append(ReportFinding(
                id: "alcohol", level: alcoholDays.count <= 1 && units <= 2 ? .caution : .bad,
                title: doctorBan ? "Có rượu bia — BS đã dặn kiêng" : "Có rượu bia",
                detail: detail,
                advice: "Nếu không tránh được: ăn no trước, tối đa 1–2 ly, không uống sau 21h, xen nước lọc; hôm sau ăn nhẹ dễ tiêu.",
                isDoctor: doctorBan))
        } else if !isDay {
            out.append(ReportFinding(id: "alcohol-ok", level: .good, title: "Không rượu bia",
                                     detail: "Cả kỳ không ghi lần uống nào — rất tốt cho dạ dày, giấc ngủ và cân nặng.",
                                     advice: nil, isDoctor: profile.doctorNotes.lowercased().contains("rượu")))
        }

        // --- Nhịp tim nghỉ
        if let r = rhrAvg {
            let level = Thresholds.restingHeartRate(bpm: r)
            let high = days.filter { ($0.restingHR ?? 0) > 85 }.count
            var detail = isDay ? "Nhịp tim nghỉ hôm nay \(Int(r.rounded())) lần/phút" : "Nhịp tim nghỉ trung bình \(Int(r.rounded())) lần/phút"
            if let p = prevRhrAvg, abs(r - p) >= 2 { detail += " (\(r > p ? "cao" : "thấp") hơn kỳ trước \(Int(abs(r - p).rounded()))" + ")" }
            if high > 0 && !isDay { detail += "; \(high) ngày trên 85" }
            detail += "."
            out.append(ReportFinding(
                id: "rhr", level: level,
                title: level == .good ? "Nhịp tim nghỉ tốt" : (level == .caution ? "Nhịp tim nghỉ hơi cao" : "Nhịp tim nghỉ cao"),
                detail: detail + (level == .good ? " Tim được nghỉ ngơi ổn." : " Thường do ngủ ít, rượu bia, căng thẳng hoặc mất nước."),
                advice: level == .good ? nil : "Ngủ đủ, uống đủ nước, bớt rượu bia vài hôm; nếu nhiều ngày liền trên 85 kèm mệt/hồi hộp thì đo huyết áp và đi khám.",
                isDoctor: false))
        }

        // --- HRV xu hướng
        if let v = hrvAvg, let p = prevHrvAvg, !isDay {
            let drop = p - v
            if drop >= 5 {
                out.append(ReportFinding(id: "hrv-drop", level: .caution, title: "Biến thiên nhịp tim giảm",
                                         detail: "HRV trung bình \(Int(v.rounded())) ms, giảm \(Int(drop.rounded())) ms so kỳ trước — cơ thể hồi phục kém hơn (thiếu ngủ, rượu bia, ốm hoặc căng thẳng).",
                                         advice: "Ưu tiên nghỉ ngơi và ngủ đủ vài ngày; tập bài thở chậm 5 phút buổi tối.", isDoctor: false))
            }
        }

        // --- Cân nặng
        if let last = weights.last {
            let level = Thresholds.bodyMass(kg: last.1)
            var detail = "Cân mới nhất \(dec(last.1)) kg"
            if let bmi = profile.bmi(kg: last.1) { detail += " (BMI \(dec(bmi))" + (bmi < 18.5 ? ", thiếu cân)" : (bmi >= 25 ? ", thừa cân)" : ")")) }
            var change: Double?
            if !isDay, let first = weights.first, first.0 != last.0 { change = last.1 - first.1 }
            else if let p = prevWeights.last { change = last.1 - p.1 }
            if let c = change, abs(c) >= 0.1 { detail += ", \(c > 0 ? "tăng" : "giảm") \(dec(abs(c))) kg" }
            detail += "."
            let wantsGain = profile.weightDirection == .gain
            let wrongWay = change.map { wantsGain ? $0 <= -0.3 : (profile.weightDirection == .lose ? $0 >= 0.3 : abs($0) >= 1) } ?? false
            let title: String
            switch (level, wrongWay) {
            case (_, true): title = wantsGain ? "Đang sụt cân" : "Cân đi ngược mục tiêu"
            case (.good, _): title = "Cân đạt mục tiêu"
            default: title = wantsGain ? "Chưa tới mục tiêu cân" : "Cân chưa về mục tiêu"
            }
            out.append(ReportFinding(
                id: "weight", level: wrongWay ? .bad : level, title: title, detail: detail,
                advice: (wrongWay || level != .good)
                    ? (wantsGain ? "Giữ đủ 6 bữa nhỏ, thêm bữa phụ giàu năng lượng dễ tiêu (sữa, trứng, khoai, bơ); cân mỗi sáng thứ 2." : "Cân mỗi sáng thứ 2, ăn đúng giờ, đi bộ sau bữa tối.")
                    : nil,
                isDoctor: false))
        }

        // --- Vận động
        if let st = stepsAvg {
            let level = Thresholds.steps(Int(st.rounded()))
            let goalDays = days.filter { ($0.steps ?? 0) >= Thresholds.stepsGoal }.count
            let active = ReportMath.mean(days.compactMap { $0.activeHours.map(Double.init) })
            var detail = isDay ? "Hôm nay \(grp(Int(st.rounded()))) bước" : "Trung bình \(grp(Int(st.rounded()))) bước/ngày, \(goalDays)/\(n) ngày đạt \(Thresholds.stepsGoalText)"
            if let a = active { detail += "; giờ có vận động \(dec(a, 0))/9" }
            detail += "."
            out.append(ReportFinding(
                id: "steps", level: level,
                title: level == .good ? "Vận động đủ" : (level == .caution ? "Vận động vừa phải" : "Ít vận động"),
                detail: detail,
                advice: level == .good ? nil : "Mỗi giờ đứng dậy đi vài phút; đi bộ 10–15 phút sau bữa tối là đủ (không cần cardio dài).",
                isDoctor: false))
        }

        // --- Triệu chứng
        let sc = symptomCounts
        if !sc.isEmpty {
            let total = sc.reduce(0) { $0 + $1.1 }
            let list = sc.prefix(4).map { "\($0.0) ×\($0.1)" }.joined(separator: ", ")
            // Triệu chứng ngày sau khi uống?
            let cal = Calendar.current
            let afterAlcohol = days.filter { d in
                guard !d.symptoms.isEmpty, let prev = cal.date(byAdding: .day, value: -1, to: d.date) else { return false }
                return (days.first { $0.date == prev }?.hadAlcohol ?? false) || d.hadAlcohol
            }.count
            var detail = "\(total) lần ghi: \(list)."
            if afterAlcohol >= 2 { detail += " \(afterAlcohol) lần rơi vào ngày uống hoặc hôm sau." }
            out.append(ReportFinding(
                id: "symptoms", level: total >= 3 ? .bad : .caution, title: "Có triệu chứng ghi lại", detail: detail,
                advice: "Ăn mềm, ấm, chia nhỏ bữa, không nằm ngay sau ăn; nếu đau nhiều, đi ngoài ra máu hay nôn thì đi khám ngay.",
                isDoctor: !profile.doctorNotes.isEmpty))
        }

        // --- Ngủ trưa
        let napTotal = days.reduce(0) { $0 + $1.napCount }
        if napTotal > 0 {
            let mins = days.reduce(0) { $0 + $1.napMinutes }
            let late = days.reduce(0) { $0 + $1.napLateCount }
            let avg = mins / napTotal
            let level = late > 0 ? .caution : Explanations.napLevel(minutes: avg)
            out.append(ReportFinding(
                id: "naps", level: level, title: "Ngủ trưa",
                detail: "\(napTotal) giấc, trung bình \(avg) phút" + (late > 0 ? "; \(late) giấc sau 15h (dễ khó ngủ đêm)." : "."),
                advice: level == .good ? nil : "Ngủ trưa 15–20 phút, trước 15h; dài quá hoặc muộn làm đêm khó ngủ.",
                isDoctor: false))
        }

        // --- Oxy máu / nhịp thở (nếu nguồn có)
        if let o = ReportMath.mean(days.compactMap(\.oxygen)) {
            let level = Thresholds.oxygenSaturation(o)
            if level != .good {
                out.append(ReportFinding(id: "oxygen", level: level, title: "Oxy máu lúc ngủ hơi thấp",
                                         detail: "Trung bình \(Int(o.rounded()))% (tốt là ≥ 95%).",
                                         advice: "Một vài đêm chưa đáng lo; nếu nhiều đêm dưới 94% hoặc hay ngáy to, hỏi BS về ngưng thở khi ngủ.",
                                         isDoctor: false))
            }
        }

        // --- Bài thở
        let breaths = days.reduce(0) { $0 + $1.breathingSessions }
        if breaths > 0 {
            let drops = days.flatMap(\.breathingDrops)
            let avg = ReportMath.mean(drops.map(Double.init))
            out.append(ReportFinding(id: "breath", level: .good, title: "Có tập bài thở",
                                     detail: "\(breaths) lần" + (avg.map { ", nhịp tim hạ trung bình \(Int($0.rounded())) nhịp mỗi bài." } ?? "."),
                                     advice: nil, isDoctor: false))
        }

        out.append(contentsOf: correlations())

        // Sắp xếp: đỏ → vàng → xanh, giữ thứ tự nhóm.
        let order: [MetricLevel: Int] = [.bad: 0, .caution: 1, .good: 2, .unknown: 3]
        return out.enumerated().sorted { a, b in
            let la = order[a.element.level] ?? 3, lb = order[b.element.level] ?? 3
            return la != lb ? la < lb : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Mối liên hệ (T-030) — app tự so hai nhóm ngày, chỉ nêu khi đủ số (≥ 2 mỗi nhóm) và khác biệt rõ

    /// Đêm SAU ngày `d` (giấc ngủ ghi ở ngày hôm sau).
    private func nightAfter(_ d: ReportDay) -> ReportDay? {
        guard let next = Calendar.current.date(byAdding: .day, value: 1, to: d.date) else { return nil }
        return days.first { $0.date == next }
    }

    /// So sánh giấc ngủ đêm sau giữa nhóm ngày `flag` và nhóm còn lại.
    private func compareNights(_ flag: (ReportDay) -> Bool) -> (a: Double, b: Double, na: Int, nb: Int, awakeA: Double?, awakeB: Double?)? {
        var A: [ReportDay] = [], B: [ReportDay] = []
        for d in days {
            guard let night = nightAfter(d), night.sleepHours != nil else { continue }
            if flag(d) { A.append(night) } else { B.append(night) }
        }
        guard A.count >= 2, B.count >= 2,
              let a = ReportMath.mean(A.compactMap(\.sleepHours)), let b = ReportMath.mean(B.compactMap(\.sleepHours)) else { return nil }
        return (a, b, A.count, B.count, ReportMath.mean(A.compactMap { $0.awakeCount.map(Double.init) }), ReportMath.mean(B.compactMap { $0.awakeCount.map(Double.init) }))
    }

    func correlations() -> [ReportFinding] {
        guard !isDay, n >= 5 else { return [] }
        var out: [ReportFinding] = []

        // 1) Dậy sớm
        let early = days.filter(\.earlyWake)
        if early.count >= 2 {
            let wakes = days.compactMap(\.wakeTime).map { d -> Double in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d); return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) }
            let avg = ReportMath.mean(wakes).map { ReportMath.minuteText($0) } ?? "–"
            out.append(ReportFinding(id: "corr-earlywake", level: .caution, title: "Mối liên hệ: hay dậy sớm",
                detail: "\(early.count)/\(n) đêm dậy trước 5h30 (giờ dậy trung bình \(avg)). Dậy sớm mà không ngủ lại được là nguyên nhân chính kéo tổng giờ ngủ xuống — thường gặp khi ngủ sớm quá, bữa tối muộn/đói đêm, rượu bia, hoặc lo nghĩ.",
                advice: "Nếu dậy trước 5h: thử lên giường muộn hơn 30 phút (22h45–23h) và có bữa phụ nhẹ lúc 21h; không nhìn giờ, nằm thư giãn/thở chậm 10 phút trước khi quyết định dậy.", isDoctor: false))
        }

        // 2) Bữa tối muộn ↔ đêm sau
        if let c = compareNights({ $0.lateDinner }) {
            let diff = c.b - c.a
            if diff >= 0.4 || ((c.awakeA ?? 0) - (c.awakeB ?? 0)) >= 0.8 {
                var t = "\(c.na) ngày ăn bữa cuối sau 20h: đêm sau ngủ \(dec(c.a)) giờ, so với \(dec(c.b)) giờ ở \(c.nb) ngày còn lại"
                if let x = c.awakeA, let y = c.awakeB, x - y >= 0.8 { t += "; thức giữa đêm nhiều hơn (\(dec(x)) vs \(dec(y)) lần)" }
                out.append(ReportFinding(id: "corr-latedinner", level: .caution, title: "Mối liên hệ: ăn tối muộn ↔ ngủ kém hơn",
                    detail: t + ". Với trào ngược, nằm sớm sau ăn dễ ợ nóng và thức giấc.",
                    advice: "Xong bữa tối trước 19h30; nếu về muộn thì ăn nhẹ dễ tiêu (cháo, súp) và đợi ≥ 2 giờ mới nằm.", isDoctor: !profile.doctorNotes.isEmpty))
            }
        }

        // 3) Ngủ trưa muộn/dài ↔ đêm sau
        if let c = compareNights({ $0.napLateCount > 0 || $0.napMinutes > 40 }), c.b - c.a >= 0.4 {
            out.append(ReportFinding(id: "corr-nap", level: .caution, title: "Mối liên hệ: ngủ trưa muộn/dài ↔ đêm ngủ ít hơn",
                detail: "\(c.na) ngày ngủ trưa sau 15h hoặc > 40 phút: đêm sau ngủ \(dec(c.a)) giờ, so với \(dec(c.b)) giờ ở \(c.nb) ngày còn lại.",
                advice: "Ngủ trưa 15–20 phút, trước 15h.", isDoctor: false))
        }

        // 4) Giờ lên giường ↔ tổng ngủ (ngủ sớm hơn có ngủ nhiều hơn không)
        let withBed = days.filter { $0.bedTime != nil && $0.sleepHours != nil }
        if withBed.count >= 5 {
            let earlyBed = withBed.filter { ReportMath.bedMinute($0.bedTime!) <= 22 * 60 + 30 }
            let lateBed = withBed.filter { ReportMath.bedMinute($0.bedTime!) > 22 * 60 + 30 }
            if earlyBed.count >= 2, lateBed.count >= 2,
               let a = ReportMath.mean(earlyBed.compactMap(\.sleepHours)), let b = ReportMath.mean(lateBed.compactMap(\.sleepHours)), abs(a - b) >= 0.4 {
                let better = a > b
                out.append(ReportFinding(id: "corr-bedtime", level: better ? .good : .caution,
                    title: better ? "Mối liên hệ: đi ngủ sớm → ngủ được nhiều hơn" : "Mối liên hệ: đi ngủ sớm nhưng không ngủ thêm được",
                    detail: "Đêm lên giường trước 22h30 ngủ \(dec(a)) giờ (\(earlyBed.count) đêm); sau 22h30 ngủ \(dec(b)) giờ (\(lateBed.count) đêm)."
                        + (better ? "" : " Lên giường sớm mà vẫn dậy sớm → tổng giờ không tăng; có thể cơ thể chỉ cần ngủ muộn hơn một chút."),
                    advice: better ? nil : "Giữ giờ dậy cố định, lùi giờ lên giường 30 phút rồi theo dõi 1 tuần.", isDoctor: false))
            }
        }

        // 5) Ngày thường vs cuối tuần
        let wk = days.filter { !$0.isWeekend }.compactMap(\.sleepHours), we = days.filter(\.isWeekend).compactMap(\.sleepHours)
        if wk.count >= 3, we.count >= 2, let a = ReportMath.mean(wk), let b = ReportMath.mean(we), abs(a - b) >= 0.7 {
            out.append(ReportFinding(id: "corr-weekend", level: .caution, title: "Mối liên hệ: ngày thường vs cuối tuần",
                detail: "Ngày thường ngủ \(dec(a)) giờ, cuối tuần \(dec(b)) giờ — lệch \(dec(abs(a - b))) giờ. Lệch nhiều là dấu hiệu nợ ngủ trong tuần (hoặc cuối tuần thức khuya).",
                advice: "Cuối tuần giữ giờ dậy lệch không quá 1 giờ so với ngày thường.", isDoctor: false))
        }

        // 6) Rượu bia ↔ HRV / nhịp nghỉ hôm sau (nếu có HRV)
        let afterAlc = alcoholDays.compactMap { nightAfter($0) }
        let normal = days.filter { d in
            guard let prev = Calendar.current.date(byAdding: .day, value: -1, to: d.date) else { return false }
            return !(days.first { $0.date == prev }?.hadAlcohol ?? false) }
        if afterAlc.count >= 2, normal.count >= 2,
           let a = ReportMath.mean(afterAlc.compactMap(\.hrv)), let b = ReportMath.mean(normal.compactMap(\.hrv)), b - a >= 5 {
            out.append(ReportFinding(id: "corr-alc-hrv", level: .bad, title: "Mối liên hệ: rượu bia ↔ HRV tụt",
                detail: "Đêm sau ngày uống, HRV \(Int(a.rounded())) ms so với \(Int(b.rounded())) ms đêm thường — cơ thể hồi phục kém hẳn sau rượu bia.",
                advice: "Đây là bằng chứng trên chính số đo của \(you): mỗi lần uống, cơ thể mất một đêm hồi phục.", isDoctor: profile.doctorNotes.lowercased().contains("rượu")))
        }

        // 7) Cấu trúc giấc ngủ (chỉ khi có giai đoạn)
        let withStages = days.filter { $0.deepMinutes != nil && ($0.sleepHours ?? 0) > 0 }
        if withStages.count >= 3 {
            let deepPct = ReportMath.mean(withStages.map { $0.deepMinutes! / ($0.sleepHours! * 60) * 100 })!
            let remPct = ReportMath.mean(withStages.map { ($0.remMinutes ?? 0) / ($0.sleepHours! * 60) * 100 })!
            let awake = ReportMath.mean(withStages.compactMap(\.awakeMinutes)) ?? 0
            let level: MetricLevel = (deepPct < 10 || remPct < 15 || awake > 60) ? .caution : .good
            out.append(ReportFinding(id: "stages", level: level, title: level == .good ? "Cấu trúc giấc ngủ ổn" : "Cấu trúc giấc ngủ chưa tốt",
                detail: "Trung bình sâu \(Int(deepPct.rounded()))% · REM \(Int(remPct.rounded()))% · thức giữa đêm \(Int(awake.rounded())) phút/đêm (\(withStages.count) đêm có giai đoạn). Tham khảo: sâu 13–23%, REM 20–25%.",
                advice: level == .good ? nil : "Ngủ sâu tăng khi không rượu bia, phòng mát tối, vận động nhẹ ban ngày; REM tăng khi ngủ đủ dài (REM dồn về sáng).", isDoctor: false))
        }
        return out
    }

    // MARK: Tổng quan + gợi ý

    func overall(findings: [ReportFinding]) -> (MetricLevel, String) {
        guard !findings.isEmpty else {
            return (.unknown, "Chưa có đủ số liệu cho kỳ này. Đeo vòng và mở app Google Health để đồng bộ, hoặc chọn ngày khác.")
        }
        let bad = findings.filter { $0.level == .bad }
        let caution = findings.filter { $0.level == .caution }
        let level: MetricLevel = bad.count >= 2 || findings.first { $0.id == "sleep-avg" }?.level == .bad ? .bad
            : (!bad.isEmpty || !caution.isEmpty ? .caution : .good)
        let worst = (bad + caution).prefix(2).map {
            $0.title.lowercased().replacingOccurrences(of: "bs ", with: "BS ")
        }
        let text: String
        switch level {
        case .good: text = isDay ? "Một ngày ổn: ngủ, tim mạch và vận động đều trong vùng tốt. Giữ nếp này." : "Kỳ này ổn: các chỉ số chính trong vùng tốt. Giữ nếp đang có."
        case .caution: text = "Nhìn chung ổn, cần để ý: " + worst.joined(separator: " và ") + "."
        case .bad: text = "Cần chỉnh lại: " + worst.joined(separator: " và ") + ". Xem gợi ý bên dưới."
        case .unknown: text = ""
        }
        return (level, text)
    }

    func advice(from findings: [ReportFinding]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for f in findings where f.level != .good {
            guard let a = f.advice, !seen.contains(a) else { continue }
            seen.insert(a); out.append(a)
            if out.count == 5 { break }
        }
        if out.isEmpty { out.append("Giữ nếp hiện tại: ngủ trước 23h, đủ bữa, đi bộ nhẹ sau bữa tối, không rượu bia.") }
        return out
    }
}

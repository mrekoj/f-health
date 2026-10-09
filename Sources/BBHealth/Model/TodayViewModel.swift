import Foundation
import Observation
import SwiftData

/// Dữ liệu màn Hôm nay: 4 chỉ số + trạng thái tải/quyền.
@Observable
@MainActor
final class TodayViewModel {
    enum State: Equatable {
        case idle
        case loading
        case needsAuthorization
        case loaded
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var sleep: SleepSummary?
    private(set) var restingHeartRate: Double?
    private(set) var steps: Int?
    private(set) var bodyMass: (kg: Double, date: Date)?
    private(set) var hrv: Double?
    private(set) var skinTemp: Double?
    /// Giấc ngủ trưa/ngủ ngày đọc được cho ngày `date` (có thể rỗng — nguồn chưa ghi giấc nào).
    private(set) var naps: [NapSummary] = []
    // T-020: sinh hiệu & vận động.
    private(set) var respiratoryRate: Double?
    private(set) var oxygenSaturation: Double?
    private(set) var distanceKm: Double?
    private(set) var activeEnergyKcal: Double?
    /// Bước theo giờ hôm nay (rỗng = nguồn chưa có số theo giờ).
    private(set) var hourlySteps: [(hour: Int, steps: Int)] = []
    /// Nhịp tim thấp nhất – cao nhất trong ngày.
    private(set) var heartRange: (min: Double, max: Double)?
    private(set) var lastUpdated: Date?

    /// "Hôm nay" của màn. **Được canh lại mỗi lần tải** (`refresh`) — app mở qua đêm ở nền thì
    /// ngày phải nhảy sang hôm sau, không được kẹt ở ngày lúc mở lần trước (lỗi PO gặp: 4h sáng CN
    /// vẫn thấy "Thứ Bảy · Chào buổi tối" và số hôm qua; pull-to-refresh vẫn tải cho ngày cũ).
    private(set) var date: Date
    /// Nguồn cố định (cho test/preview); nếu nil thì lấy theo cấu hình `AppSettings`.
    private let providerOverride: (any HealthStoreProvider)?

    init(providerOverride: (any HealthStoreProvider)? = nil, date: Date = Date()) {
        self.providerOverride = providerOverride
        self.date = date
    }

    private var source: HealthSource { AppSettings.shared.source }
    private func provider() -> any HealthStoreProvider {
        providerOverride ?? HealthStoreFactory.make(for: source)
    }

    /// Có hiển thị ô HRV / nhiệt độ da không (nguồn Google và đã có số).
    var showsGoogleMetrics: Bool { source.usesGoogle }
    var hasHRV: Bool { hrv != nil }
    var hasSkinTemp: Bool { skinTemp != nil }

    // MARK: - Hiển thị

    /// "Thứ Tư, 30 tháng 9"
    var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEE, d 'tháng' M"
        let s = f.string(from: date)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Lời chào theo giờ.
    var greeting: String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 4..<11: return "Chào buổi sáng"
        case 11..<13: return "Chào buổi trưa"
        case 13..<18: return "Chào buổi chiều"
        default: return "Chào buổi tối"
        }
    }

    /// 1 câu tóm tắt dễ hiểu cho cả ngày.
    var summary: String {
        // Xưng hô + lời khuyên ăn theo hồ sơ; hồ sơ trống → "bạn" và lời khuyên chung (không "6 bữa").
        let profile = HealthProfileStore.current
        let you = profile.you
        var first: String
        switch sleepLevel {
        case .good: first = "Đêm qua \(you) ngủ đủ giấc"
        case .caution: first = "Đêm qua \(you) ngủ hơi thiếu"
        case .bad: first = "Đêm qua \(you) ngủ ít"
        case .unknown: first = "Chưa có số giấc ngủ đêm qua"
        }
        let eat: String
        if !profile.isEmpty && profile.weightDirection == .gain {
            eat = bodyMassLevel == .good ? "giữ đều 6\u{00A0}bữa" : "ăn đủ 6\u{00A0}bữa nhỏ"
        } else {
            eat = "ăn đúng bữa"
        }
        let bed = sleepLevel == .good ? "giữ giờ ngủ trước 23h" : "lên giường trước 23h"
        return "\(first) — hôm nay nên \(eat) và \(bed)."
    }

    var sleepLevel: MetricLevel { Thresholds.sleep(hours: sleep?.totalHours) }
    var heartLevel: MetricLevel { Thresholds.restingHeartRate(bpm: restingHeartRate) }
    var stepsLevel: MetricLevel { Thresholds.steps(steps) }
    var bodyMassLevel: MetricLevel { Thresholds.bodyMass(kg: bodyMass?.kg) }
    var hrvLevel: MetricLevel { Thresholds.heartRateVariability(ms: hrv) }
    var skinTempLevel: MetricLevel { Thresholds.skinTemperature(delta: skinTemp) }
    var respiratoryLevel: MetricLevel { Thresholds.respiratoryRate(respiratoryRate) }
    var oxygenLevel: MetricLevel { Thresholds.oxygenSaturation(oxygenSaturation) }
    var distanceLevel: MetricLevel { Thresholds.distance(km: distanceKm) }
    var activeEnergyLevel: MetricLevel { Thresholds.activeEnergy(activeEnergyKcal) }
    /// Ngày đang diễn ra: chưa tô đỏ khi số giờ còn lại trong ngày (tới 22h) vẫn đủ để đạt 9 giờ
    /// — tránh cảnh 6h sáng đã "Nên cải thiện" vì mới 0 giờ vận động.
    var activeHoursLevel: MetricLevel {
        let level = Thresholds.activeHours(activeHours)
        guard level == .bad, let h = activeHours else { return level }
        let hoursLeft = max(0, 22 - Calendar.current.component(.hour, from: date))
        return h + hoursLeft >= ActiveHours.goal ? .caution : .bad
    }
    var heartRangeLevel: MetricLevel { Thresholds.heartRateRange(min: heartRange?.min, max: heartRange?.max) }

    // MARK: - Sinh hiệu & vận động (T-020)

    /// Số giờ có ≥ 250 bước; nil khi nguồn không có bước theo giờ.
    var activeHours: Int? { hourlySteps.isEmpty ? nil : ActiveHours.count(hourlySteps) }
    /// Có ít nhất một số để hiện mục "Sinh hiệu & vận động" không.
    var hasVitals: Bool {
        respiratoryRate != nil || oxygenSaturation != nil || distanceKm != nil
            || activeEnergyKcal != nil || activeHours != nil || heartRange != nil
    }
    var respiratoryValueText: String { respiratoryRate.map { Self.decimal($0, digits: 1) } ?? "—" }
    var oxygenValueText: String { oxygenSaturation.map { "\(Int($0.rounded()))" } ?? "—" }
    var distanceValueText: String { distanceKm.map { Self.decimal($0, digits: 1) } ?? "—" }
    var activeEnergyValueText: String { activeEnergyKcal.map { Self.grouped(Int($0.rounded())) } ?? "—" }
    var activeHoursValueText: String { activeHours.map { "\($0)" } ?? "—" }
    var heartRangeValueText: String {
        guard let r = heartRange else { return "—" }
        return "\(Int(r.min.rounded()))–\(Int(r.max.rounded()))"
    }

    var hrvValueText: String {
        guard let v = hrv else { return "—" }
        return "\(Int(v.rounded()))"
    }
    /// Nhiệt độ da hiện có dấu +/− (chênh so với nền).
    var skinTempValueText: String {
        guard let v = skinTemp else { return "—" }
        let sign = v > 0 ? "+" : (v < 0 ? "−" : "")
        return sign + Self.decimal(abs(v), digits: 1)
    }
    var hrvCaption: String {
        switch hrvLevel {
        case .good: return "Hồi phục tốt"
        case .caution: return "Theo dõi xu hướng"
        case .bad: return "Thấp — nghỉ nhiều hơn"
        case .unknown: return "Đo lúc ngủ"
        }
    }
    var skinTempCaption: String {
        switch skinTempLevel {
        case .good: return "So với nền — ổn định"
        case .caution: return "Lệch nhẹ so với nền"
        case .bad: return "Lệch nhiều — để ý sức khoẻ"
        case .unknown: return "So với nền"
        }
    }

    var sleepValueText: String {
        guard let h = sleep?.totalHours else { return "—" }
        return Self.decimal(h, digits: 1)
    }

    /// "Thức 2 lần" + xuống dòng + "22:48 → 06:02"
    var sleepDetailText: String? {
        guard let s = sleep else { return nil }
        var parts: [String] = []
        parts.append(s.awakeCount == 0 ? "Không thức giấc" : "Thức \(s.awakeCount) lần")
        if let b = s.bedTime, let w = s.wakeTime {
            parts.append("\(Self.time(b)) → \(Self.time(w))")
        }
        return parts.joined(separator: "\n")
    }

    var sleepProgress: Double { (sleep?.totalHours ?? 0) / Thresholds.sleepGoalHours }
    var bedTimeText: String? { sleep?.bedTime.map(Self.time) }
    var wakeTimeText: String? { sleep?.wakeTime.map(Self.time) }
    var awakeText: String? {
        guard let s = sleep else { return nil }
        return s.awakeCount == 0 ? "Không thức giấc" : "Thức giấc \(s.awakeCount) lần"
    }

    var stepsProgress: Double { Double(steps ?? 0) / Double(Thresholds.stepsGoal) }

    /// "còn 4,8 kg tới mục tiêu 53 kg" (tăng cân) / "còn 2 kg cần giảm" (giảm cân) / "lệch 1,2 kg" (giữ cân).
    var weightGoalText: String? {
        guard let m = bodyMass else { return nil }
        let goal = Thresholds.weightGoalKg, goalText = Thresholds.weightGoalText
        switch HealthProfileStore.current.weightDirection {
        case .gain:
            let left = goal - m.kg
            if left <= 0 { return "Đã đạt mục tiêu \(goalText)" }
            return "Còn \(Self.decimal(left, digits: 1)) kg tới mục tiêu \(goalText)"
        case .lose:
            let left = m.kg - goal
            if left <= 0 { return "Đã đạt mục tiêu \(goalText)" }
            return "Còn \(Self.decimal(left, digits: 1)) kg cần giảm tới \(goalText)"
        case .keep:
            let d = m.kg - goal
            if abs(d) <= 0.5 { return "Đang giữ đúng mức \(goalText)" }
            return "Lệch \(Self.decimal(abs(d), digits: 1)) kg so với mức \(goalText)"
        }
    }
    /// Tiến độ tới mục tiêu: tăng cân tính từ mốc (mục tiêu − 8 kg); giảm cân từ (mục tiêu + 8 kg); giữ cân = 1.
    var weightProgress: Double {
        guard let m = bodyMass else { return 0 }
        let goal = Thresholds.weightGoalKg
        switch HealthProfileStore.current.weightDirection {
        case .gain: return (m.kg - (goal - 8)) / 8
        case .lose: return ((goal + 8) - m.kg) / 8
        case .keep: return 1 - min(1, abs(m.kg - goal) / 3)
        }
    }

    /// Đoạn "Của bạn hôm nay" trong sheet giải thích.
    func todayNote(for metric: Metric) -> String {
        switch metric {
        case .sleep:
            guard let s = sleep else { return "Chưa có số giấc ngủ đêm qua." }
            let missing = Thresholds.sleepGoalHours - s.totalHours
            var t = "Đêm qua anh ngủ \(sleepValueText) giờ"
            t += missing > 0 ? ", thiếu \(Self.decimal(missing, digits: 1)) giờ so với mục tiêu \(Thresholds.sleepGoalText)." : ", đạt mục tiêu \(Thresholds.sleepGoalText)."
            if let b = bedTimeText, let w = wakeTimeText { t += " Ngủ lúc \(b), dậy lúc \(w)." }
            if s.awakeCount > 0 { t += " Thức giấc \(s.awakeCount) lần giữa đêm." }
            return t
        case .restingHeartRate:
            guard restingHeartRate != nil else { return "Chưa có số nhịp tim nghỉ hôm nay." }
            switch heartLevel {
            case .good: return "Hôm nay \(heartValueText) lần/phút — nằm trong vùng tốt (≤ 70). Cơ thể đang được nghỉ ngơi ổn."
            case .caution: return "Hôm nay \(heartValueText) lần/phút — hơi cao hơn mức tốt. Xem lại giấc ngủ và rượu bia tối qua."
            default: return "Hôm nay \(heartValueText) lần/phút — cao. Nghỉ ngơi, uống đủ nước; nếu kéo dài kèm mệt thì đi khám."
            }
        case .steps:
            guard let st = steps else { return "Chưa có số bước hôm nay." }
            let left = Thresholds.stepsGoal - st
            if left <= 0 { return "Hôm nay anh đã đi \(stepsValueText) bước — đạt mục tiêu \(Thresholds.stepsGoalText). Không cần đi thêm." }
            return "Hôm nay anh đã đi \(stepsValueText) bước, còn \(Self.grouped(left)) bước nữa là đạt \(Thresholds.stepsGoalText). Một vòng đi bộ nhẹ sau bữa tối là đủ."
        case .bodyMass:
            guard let m = bodyMass else { return "Chưa có số cân nặng." }
            let goalText = Thresholds.weightGoalText
            switch HealthProfileStore.current.weightDirection {
            case .gain:
                let left = Thresholds.weightGoalKg - m.kg
                if left <= 0 { return "Cân mới nhất \(bodyMassValueText) kg — đã đạt mục tiêu. Giữ đều 6 bữa." }
                return "Cân mới nhất \(bodyMassValueText) kg, còn \(Self.decimal(left, digits: 1)) kg tới mục tiêu \(goalText). Tăng đều 0,25–0,5 kg mỗi tuần là đẹp."
            case .lose:
                let left = m.kg - Thresholds.weightGoalKg
                if left <= 0 { return "Cân mới nhất \(bodyMassValueText) kg — đã đạt mục tiêu \(goalText)." }
                return "Cân mới nhất \(bodyMassValueText) kg, còn \(Self.decimal(left, digits: 1)) kg cần giảm tới \(goalText). Giảm đều 0,25–0,5 kg mỗi tuần là an toàn."
            case .keep:
                return "Cân mới nhất \(bodyMassValueText) kg (mức giữ \(goalText)). Cân đều mỗi tuần để thấy xu hướng."
            }
        case .heartRateVariability:
            guard hrv != nil else { return "Chưa có số HRV (cần nguồn Google Health)." }
            switch hrvLevel {
            case .good: return "Đêm qua HRV \(hrvValueText) ms — cơ thể hồi phục tốt. Giữ nếp ngủ và tránh rượu bia buổi tối."
            case .caution: return "Đêm qua HRV \(hrvValueText) ms — ở mức vừa. Nhìn xu hướng vài ngày; nếu tụt dần thì để ý ngủ và rượu bia."
            default: return "Đêm qua HRV \(hrvValueText) ms — thấp so với thường ngày. Hôm nay nên nghỉ ngơi, uống đủ nước, tránh rượu bia."
            }
        case .respiratoryRate:
            guard respiratoryRate != nil else { return "Nguồn chưa có số nhịp thở đêm qua." }
            switch respiratoryLevel {
            case .good: return "Đêm qua anh thở trung bình \(respiratoryValueText) lần/phút — trong vùng bình thường (12–20)."
            case .caution: return "Đêm qua \(respiratoryValueText) lần/phút — hơi lệch vùng bình thường. Tối qua có rượu bia, căng thẳng hay người hơi sốt không?"
            default: return "Đêm qua \(respiratoryValueText) lần/phút — lệch nhiều. Nếu kèm sốt, ho, khó thở thì nên đi khám."
            }
        case .oxygenSaturation:
            guard oxygenSaturation != nil else { return "Nguồn chưa có số oxy máu đêm qua." }
            switch oxygenLevel {
            case .good: return "Oxy máu đêm qua \(oxygenValueText)% — tốt (≥ 95%)."
            case .caution: return "Oxy máu đêm qua \(oxygenValueText)% — hơi thấp. Một đêm chưa đáng lo; xem thêm vài đêm nữa."
            default: return "Oxy máu đêm qua \(oxygenValueText)% — thấp. Nếu nhiều đêm như vậy hoặc anh hay ngáy to, hãy hỏi BS về ngưng thở khi ngủ."
            }
        case .distance:
            guard distanceKm != nil else { return "Nguồn chưa có số quãng đường hôm nay." }
            switch distanceLevel {
            case .good: return "Hôm nay anh đã đi \(distanceValueText) km — đủ rồi, không cần đi thêm."
            case .caution: return "Hôm nay anh đã đi \(distanceValueText) km. Một vòng đi bộ chậm sau bữa tối là đạt 3 km."
            default: return "Hôm nay anh mới đi \(distanceValueText) km. Đứng dậy đi lại nhẹ nhàng vài lần trong ngày nhé."
            }
        case .activeEnergy:
            guard activeEnergyKcal != nil else { return "Nguồn chưa có số calo vận động hôm nay." }
            return "Hôm nay anh đốt thêm khoảng \(activeEnergyValueText) kcal khi đi lại, vận động. Nhớ bù lại bằng đủ 6 bữa — ăn đủ mới tăng được cân."
        case .activeHours:
            guard let h = activeHours else { return "Nguồn chưa có số bước theo giờ hôm nay." }
            switch activeHoursLevel {
            case .good: return "Hôm nay có \(h) giờ anh đi lại ≥ 250 bước — đạt mục tiêu 9 giờ. Rất tốt!"
            default: return "Hôm nay có \(h)/9 giờ anh đi lại ≥ 250 bước. Cứ mỗi giờ đứng dậy đi vài phút là lên dần."
            }
        case .liveHeartRate:
            return "Mở Nhịp tim → nút đo trực tiếp để xem nhịp tim ngay lúc này từ vòng."
        case .heartRateRange:
            guard heartRange != nil else { return "Nguồn chưa có số nhịp tim trong ngày." }
            switch heartRangeLevel {
            case .good: return "Hôm nay tim anh dao động \(heartRangeValueText) lần/phút — bình thường theo việc anh làm."
            case .caution: return "Hôm nay tim anh dao động \(heartRangeValueText) lần/phút. Lúc cao thường do đi nhanh, cà phê hay hồi hộp; chạm vào ô để xem giờ nào."
            default: return "Hôm nay tim anh dao động \(heartRangeValueText) lần/phút — có lúc khá lệch. Nếu lúc đó đang ngồi yên, kèm hồi hộp/chóng mặt thì nên đi khám."
            }
        case .skinTemperature:
            guard let t = skinTemp else { return "Chưa có số nhiệt độ da (cần nguồn Google Health)." }
            let word = t > 0 ? "ấm hơn" : (t < 0 ? "mát hơn" : "ngang")
            switch skinTempLevel {
            case .good: return "Nhiệt độ da đêm qua \(skinTempValueText) °C so với nền — trong khoảng bình thường."
            case .caution: return "Nhiệt độ da \(skinTempValueText) °C (\(word) nền một chút). Nếu kèm mệt hoặc phòng nóng thì để ý nghỉ ngơi."
            default: return "Nhiệt độ da \(skinTempValueText) °C, \(word) nền rõ rệt. Để ý xem có sắp ốm không, giữ phòng thoáng mát."
            }
        }
    }

    var heartValueText: String {
        guard let b = restingHeartRate else { return "—" }
        return "\(Int(b.rounded()))"
    }

    var stepsValueText: String {
        guard let s = steps else { return "—" }
        return Self.grouped(s)
    }

    var bodyMassValueText: String {
        guard let m = bodyMass else { return "—" }
        return Self.decimal(m.kg, digits: 1)
    }

    /// "Đo 7:05 hôm nay" / "Đo 29/9"
    var bodyMassDetailText: String? {
        guard let m = bodyMass else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(m.date) { return "Đo \(Self.time(m.date)) hôm nay" }
        if cal.isDateInYesterday(m.date) { return "Đo hôm qua" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "d/M"
        return "Đo ngày \(f.string(from: m.date))"
    }

    // MARK: - Giấc ngủ trưa (hiển thị trên Card)

    var hasNaps: Bool { !naps.isEmpty }
    var napCount: Int { naps.count }
    var napTotalMinutes: Int { naps.reduce(0) { $0 + $1.minutes } }
    var latestNap: NapSummary? { naps.max { $0.start < $1.start } }

    /// "2 giấc · 38 phút" — tóm tắt số giấc trưa hôm nay.
    var napSummaryText: String {
        "\(napCount) giấc · \(napTotalMinutes) phút"
    }

    /// Tự lưu giấc trưa gần đây vào SwiftData (chống trùng) — gọi sau khi màn Hôm nay tải xong.
    func autoLogNaps(into context: ModelContext) async {
        await NapAutoLogger.scanAndLog(provider: provider(), context: context,
                                       now: date, source: NapAutoLogger.sourceLabel(for: source))
    }

    // MARK: - Tải dữ liệu

    /// Lần đầu mở màn: kiểm tra quyền rồi tải.
    func loadIfNeeded() async {
        guard state == .idle else { return }
        if await provider().authorizationRequestNeeded() {
            state = .needsAuthorization
            return
        }
        await refresh()
    }

    /// Đổi nguồn trong Cài đặt → tải lại từ đầu.
    func reload() async {
        state = .idle
        await loadIfNeeded()
    }

    /// App quay lại foreground / màn Hôm nay hiện lại → tự tải số mới (Fitbit đồng bộ dần nên lần
    /// mở trước có thể còn dở). Tôn trọng các trạng thái chờ để KHÔNG tạo vòng lặp tải vô hạn:
    /// chỉ tải lại khi đã `.loaded`, hoặc đi tiếp luồng xin quyền khi còn `.idle`.
    func refreshOnForeground() async {
        switch state {
        case .loaded, .failed: await refresh()   // .failed: thử lại khi quay lại app
        case .idle: await loadIfNeeded()
        default: break   // .loading / .needsAuthorization: để yên, tránh tải chồng
        }
    }

    func requestAuthorization() async {
        state = .loading
        do {
            try await provider().requestAuthorization()
            await refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func refresh() async {
        // Canh lại "hôm nay" trước khi tải: qua nửa đêm thì ngày, lời chào, bữa tiếp theo đều đổi theo.
        // (`DebugOptions.now` = giờ thật trên máy; chỉ cố định khi chụp màn với -BBHNow.)
        date = DebugOptions.now
        if state != .loaded { state = .loading }
        let provider = provider()
        let source = source
        do {
            async let s = provider.sleepSummary(for: date)
            async let h = provider.restingHeartRate(for: date)
            async let st = provider.steps(for: date)
            async let m = provider.latestBodyMass()
            async let v = provider.heartRateVariability(for: date)
            async let t = provider.skinTemperature(for: date)
            async let n = provider.daytimeSleeps(for: date)
            async let en = provider.estimatedDaytimeNaps(for: date)
            // T-020: chỉ số phụ — lỗi từng cái thì bỏ qua (không làm hỏng cả màn).
            async let br = (try? await provider.respiratoryRate(for: date)) ?? nil
            async let ox = (try? await provider.oxygenSaturation(for: date)) ?? nil
            async let dist = (try? await provider.distanceKm(for: date)) ?? nil
            async let kcal = (try? await provider.activeEnergyKcal(for: date)) ?? nil
            async let hourly = (try? await provider.hourlySteps(for: date)) ?? []
            async let range = Self.heartRange(provider: provider, date: date)
            let (sleepResult, hrResult, stepsResult, massResult, hrvResult, tempResult, napResult, estNapResult)
                = try await (s, h, st, m, v, t, n, en)
            sleep = sleepResult
            restingHeartRate = hrResult
            steps = stepsResult
            bodyMass = massResult
            hrv = hrvResult
            skinTemp = tempResult
            // Gộp phiên-ngủ thật + giấc HR-dò (bỏ HR-dò chồng lấn phiên ngủ — ưu tiên dữ liệu thật).
            var mergedNaps = napResult
            for e in estNapResult where !napResult.contains(where: { $0.overlaps(e) }) {
                mergedNaps.append(e)
            }
            naps = mergedNaps.sorted { $0.start < $1.start }
            respiratoryRate = await br
            oxygenSaturation = await ox
            distanceKm = await dist
            activeEnergyKcal = await kcal
            hourlySteps = await hourly
            heartRange = await range
            lastUpdated = Date()
            AppSettings.shared.recordUpdate(for: source)
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Dải thấp–cao hôm nay: ưu tiên tính từ nhịp tim theo giờ (khớp màn Nhịp tim chi tiết),
    /// không có thì lấy `heartRateDailyRanges` của đúng ngày (bỏ trường hợp chỉ có nhịp nghỉ min = max).
    nonisolated private static func heartRange(provider: any HealthStoreProvider,
                                               date: Date) async -> (min: Double, max: Double)? {
        if let points = (try? await provider.intradayHeartRate(for: date)) ?? nil,
           let lo = points.map(\.bpm).min(), let hi = points.map(\.bpm).max() {
            return (lo, hi)
        }
        if let r = (try? await provider.heartRateDailyRanges(from: date, to: date))?.last, r.max > r.min {
            return (r.min, r.max)
        }
        return nil
    }

    // MARK: - Định dạng số kiểu Việt (dấu phẩy thập phân, chấm hàng nghìn)

    nonisolated static func decimal(_ value: Double, digits: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: value as NSNumber) ?? "\(value)"
    }

    nonisolated static func grouped(_ value: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.numberStyle = .decimal
        return f.string(from: value as NSNumber) ?? "\(value)"
    }

    nonisolated static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "07:05, 30/9" — dùng cho "cập nhật lần cuối".
    nonisolated static func timeAndDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = Calendar.current.isDateInToday(date) ? "HH:mm 'hôm nay'" : "HH:mm, d/M"
        return f.string(from: date)
    }
}

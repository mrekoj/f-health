import Foundation

/// Đổi `HealthReport` thành **văn bản** (Markdown) — cho nút "Sao chép cho AI", "Chia sẻ", và sau này là
/// nội dung gửi thẳng lên Gemini/Claude (T-026). Người dùng xem được đúng nội dung này trước khi gửi.
enum HealthReportText {

    /// Lời dẫn cho AI (đặt đầu gói khi dán vào ChatGPT/Gemini/Claude hoặc gửi qua API).
    static func aiPrompt(for report: HealthReport) -> String {
        let p = report.profile
        let name = p.displayName.isEmpty ? p.addressAs : "\(p.addressAs) \(p.displayName)"
        return """
        Bạn là chuyên gia sức khoẻ (giấc ngủ, tim mạch, dinh dưỡng, lối sống) đang tư vấn cho \(name) \
        bằng tiếng Việt đời thường, dễ hiểu, không thuật ngữ tiếng Anh, xưng hô "\(p.addressAs)".
        Dưới đây là hồ sơ và số liệu \(report.period.kind == .day ? "1 ngày" : "\(report.period.kind.days) ngày") \
        đo từ vòng đeo tay (giấc ngủ, nhịp tim, bước, cân) cùng nhật ký tự ghi (bữa ăn, rượu bia, triệu chứng), \
        kèm nhận xét tự động của app theo ngưỡng cá nhân.

        Hãy phân tích và trả lời theo thứ tự:
        1. Tình trạng chung (2–3 câu).
        2. Giấc ngủ — đủ chưa, giờ giấc có đều không, điều gì đang kéo giấc ngủ xuống.
        3. Tim mạch — nhịp tim nghỉ, biến thiên nhịp tim (nếu có) nói lên điều gì.
        4. Cân nặng & ăn uống — đang đi đúng hướng mục tiêu chưa, bữa nào thiếu.
        5. Vận động.
        6. Mối liên hệ đáng chú ý (vd rượu bia ↔ giấc ngủ/nhịp tim, triệu chứng ↔ bữa ăn).
        7. Điều cần lưu ý / khi nào nên đi khám (bám lời bác sĩ dặn trong hồ sơ).
        8. 3 việc cụ thể nên làm trong \(report.period.kind.days >= 30 ? "tháng" : "tuần") tới.

        Nguyên tắc: không chẩn đoán bệnh, không kê thuốc, không thay bác sĩ; số nào thiếu thì nói là thiếu, \
        không bịa. Ưu tiên lời khuyên ngắn, làm được ngay.
        """
    }

    /// Lời dặn hệ thống cho **màn hỏi đáp** (T-027): lời dẫn + số liệu kỳ hiện tại + cách dùng công cụ.
    static func chatSystemPrompt(for report: HealthReport, today: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EEEE dd/MM/yyyy"
        return aiPrompt(for: report) + """


        Đây là HỎI ĐÁP: trả lời đúng câu hỏi, ngắn gọn (3–8 câu hoặc vài gạch đầu dòng), dẫn số cụ thể,         không lặp lại cả báo cáo. Hôm nay là \(f.string(from: today)) (ngày \(HealthDataTools.ymd(today))).         Khi cần số liệu ngoài phần đã có (một ngày/đêm cụ thể, nhịp tim theo giờ, khoảng ngày khác),         hãy GỌI CÔNG CỤ thay vì đoán; mỗi lượt nên gọi tối đa 3 công cụ. Giấc ngủ của "đêm qua" ghi ở ngày hôm nay.         Trình bày: in đậm số quan trọng, gạch đầu dòng "- ", không dùng bảng, không dấu #.

        ===== SỐ LIỆU KỲ ĐANG XEM =====
        \(markdown(report, includePrompt: false))
        """
    }

    /// Lời dặn cho **Phân tích sâu** (T-031): model mạnh, nhìn xu hướng dài, tiến độ mục tiêu, so kỳ trước.
    static func deepSystemPrompt(for report: HealthReport) -> String {
        let p = report.profile
        let name = p.displayName.isEmpty ? p.addressAs : "\(p.addressAs) \(p.displayName)"
        return """
        Bạn là bác sĩ gia đình kiêm chuyên gia giấc ngủ và dinh dưỡng, đang làm PHÂN TÍCH SÂU định kỳ cho \(name) \
        bằng tiếng Việt đời thường, xưng hô "\(p.addressAs)". Dữ liệu: hồ sơ (bệnh nền, lời BS dặn), số liệu \
        \(report.period.kind.days) ngày từ vòng đeo tay + nhật ký tự ghi, nhận xét và mối liên hệ app đã tính, \
        bảng theo tuần và theo ngày. Hãy đọc kỹ TOÀN BỘ bảng số trước khi kết luận; mọi nhận định phải dẫn số/ngày cụ thể.

        Viết theo thứ tự (mỗi mục một dòng tiêu đề in đậm dạng **1. …**, dưới là gạch đầu dòng "- "; không bảng, không dấu #):
        1. Bức tranh chung — 3 câu: đang tốt lên hay xấu đi, vì sao.
        2. Tiến độ mục tiêu — cân nặng (tốc độ kg/tuần so với mục tiêu), giấc ngủ (số đêm đạt, xu hướng tuần này so tuần trước), vận động.
        3. Xu hướng theo tuần — tuần nào tốt nhất/kém nhất, điều gì khác nhau giữa chúng.
        4. Giấc ngủ chi tiết — giờ ngủ/dậy, dậy sớm, thức giữa đêm, cấu trúc sâu/REM; nguyên nhân khả dĩ từ nhật ký.
        5. Tim mạch — nhịp nghỉ, HRV: xu hướng, ngày bất thường, liên hệ rượu bia/ngủ.
        6. Ăn uống & triệu chứng — bữa muộn, kiêng khem, triệu chứng lặp lại.
        7. Điều đáng mừng — 2–3 thứ đang làm tốt, giữ lại.
        8. Dấu hiệu cần đi khám / hỏi bác sĩ (bám lời BS dặn trong hồ sơ) — nếu không có, nói rõ là chưa thấy.
        9. Kế hoạch 2 tuần tới — 3 việc cụ thể, đo được, và 1 "thí nghiệm" nhỏ để kiểm chứng (vd xong bữa tối trước 19h30 trong 7 ngày, xem giờ dậy có muộn hơn không).

        Dài khoảng 500–800 chữ. Không chào hỏi. Không chẩn đoán bệnh, không kê thuốc; số nào thiếu thì nói thiếu, không bịa.
        """
    }

    /// Lời dặn hệ thống khi app **tự gọi AI** (T-026): lời dẫn + quy ước trình bày để hiển thị đẹp trong app.
    static func systemPrompt(for report: HealthReport) -> String {
        aiPrompt(for: report) + """


        Trình bày (hiển thị trên điện thoại, chữ to):
        - Mỗi mục bắt đầu bằng một dòng tiêu đề in đậm dạng **1. Tình trạng chung** (không dùng dấu # và không dùng bảng).
        - Dưới tiêu đề: 1–3 câu ngắn hoặc gạch đầu dòng "- ". In đậm con số hoặc ý quan trọng.
        - Tổng cộng khoảng 250–400 chữ. Không chào hỏi, không nhắc lại toàn bộ số liệu, đi thẳng vào nhận định.
        """
    }

    /// Toàn bộ gói: lời dẫn (tuỳ chọn) + hồ sơ + số liệu + nhận xét.
    static func markdown(_ r: HealthReport, includePrompt: Bool, includeProfile: Bool = true) -> String {
        var s = ""
        if includePrompt { s += aiPrompt(for: r) + "\n\n---\n\n" }
        s += "# Báo cáo sức khoẻ — \(r.period.kind.label.lowercased()) \(r.period.rangeText)\n"
        s += "Nguồn: \(r.sourceTitle)\(r.isMock ? " (số giả lập trên máy ảo)" : "") · Tạo lúc \(TodayViewModel.timeAndDate(r.generatedAt))\n\n"
        if includeProfile { s += profileSection(r.profile) }
        s += overviewSection(r)
        s += findingsSection(r)
        s += weeklySection(r)
        s += dailyTable(r)
        s += nightsSection(r)
        s += heartHourlySection(r)
        s += diarySection(r)
        s += "\n_Báo cáo do app BBHealth tự tổng hợp theo ngưỡng cá nhân; chỉ để tham khảo, không thay bác sĩ._\n"
        return s
    }

    /// Lời dặn ngắn cho AI trên máy (mô hình nhỏ: dặn ít, rõ).
    static func compactSystemPrompt(for report: HealthReport) -> String {
        let p = report.profile
        return """
        Bạn là chuyên gia sức khoẻ tư vấn cho "\(p.addressAs)" bằng tiếng Việt đời thường, ngắn gọn, dẫn số cụ thể. \
        Trả lời theo 4 mục in đậm: **Tình trạng chung**, **Giấc ngủ**, **Tim mạch & vận động**, **Việc nên làm** (3 gạch đầu dòng). \
        Tổng ≤ 200 chữ. Không chẩn đoán bệnh, không thay bác sĩ; thiếu số thì nói thiếu.
        """
    }

    /// Gói **rút gọn** cho AI trên máy (cửa sổ ngữ cảnh nhỏ ~4.000 token): hồ sơ 3 dòng, tổng quan, nhận xét,
    /// bảng ngày tối giản (tối đa 14 dòng). Mục tiêu ≤ ~3.500 ký tự.
    static func compact(_ r: HealthReport) -> String {
        let p = r.profile
        var s = "Báo cáo \(r.period.kind.label.lowercased()) \(r.period.rangeText).\n"
        s += "Hồ sơ: \(p.age) tuổi, \(p.sex.label.lowercased())"
        if let h = p.heightCm { s += ", cao \(Int(h)) cm" }
        s += "; mục tiêu \(p.weightDirection.label.lowercased()) về \(Thresholds.weightGoalText), ngủ ≥ \(Thresholds.sleepGoalText).\n"
        let cond = p.conditions.split(separator: "\n").prefix(3).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "; ")
        if !cond.isEmpty { s += "Bệnh nền: \(cond).\n" }
        let doc = p.doctorNotes.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        if !doc.isEmpty { s += "BS dặn: \(String(doc.prefix(160))).\n" }
        s += "Đánh giá chung: \(r.overallLevel.label) — \(r.overallText)\n"
        for st in r.stats { s += "- \(st.title): \(st.value) \(st.unit) (\(st.level.label))\(st.delta.map { ", \($0)" } ?? "")\n" }
        s += "Nhận xét:\n"
        for f in r.findings.prefix(8) { s += "- [\(f.level.label)] \(f.title): \(String(f.detail.prefix(140)))\n" }
        if r.days.count > 1 {
            let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
            s += "Theo ngày (ngủ giờ | đi ngủ→dậy | nhịp nghỉ | bước | rượu | triệu chứng):\n"
            for d in r.days.suffix(14) {
                let bw = d.bedTime != nil && d.wakeTime != nil ? "\(TodayViewModel.time(d.bedTime!))→\(TodayViewModel.time(d.wakeTime!))" : "–"
                s += "\(f.string(from: d.date)): \(d.sleepHours.map { TodayViewModel.decimal($0, digits: 1) } ?? "–") | \(bw) | \(d.restingHR.map { "\(Int($0.rounded()))" } ?? "–") | \(d.steps.map { TodayViewModel.grouped($0) } ?? "–") | \(d.hadAlcohol ? "\(Int(d.alcoholUnits.rounded())) ly" : "0") | \(d.symptoms.isEmpty ? "–" : d.symptoms.prefix(2).joined(separator: ","))\n"
            }
        } else if let d = r.days.first {
            if let deep = d.deepMinutes { s += "Giai đoạn đêm qua: sâu \(Int(deep))', REM \(Int(d.remMinutes ?? 0))', thức \(Int(d.awakeMinutes ?? 0))'\(d.awakeEpisodes.isEmpty ? "" : " (" + d.awakeEpisodes.joined(separator: ", ") + ")").\n" }
            if !d.meals.isEmpty { s += "Bữa ăn: " + d.meals.prefix(6).joined(separator: "; ") + "\n" }
        }
        return String(s.prefix(3800))
    }

    // MARK: - Từng phần

    private static func profileSection(_ p: HealthProfile) -> String {
        var s = "## Hồ sơ\n"
        var basics: [String] = []
        if !p.displayName.isEmpty { basics.append("Tên gọi: \(p.displayName) (\(p.addressAs))") }
        basics.append("\(p.age) tuổi, \(p.sex.label.lowercased())")
        if let h = p.heightCm { basics.append("cao \(TodayViewModel.decimal(h, digits: 0)) cm") }
        s += "- " + basics.joined(separator: " · ") + "\n"
        s += "- Mục tiêu: \(p.weightDirection.label.lowercased()) về \(Thresholds.weightGoalText); ngủ ≥ \(Thresholds.sleepGoalText)/đêm; \(Thresholds.stepsGoalText) bước/ngày\n"
        func block(_ title: String, _ text: String) {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            s += "- \(title):\n" + t.split(separator: "\n").map { "  - \($0.trimmingCharacters(in: .whitespaces))" }.joined(separator: "\n") + "\n"
        }
        block("Bệnh nền / tình trạng", p.conditions)
        block("Bác sĩ dặn", p.doctorNotes)
        block("Ăn uống", p.dietNotes)
        block("Thuốc / bổ sung", p.medications)
        block("Lối sống", p.lifestyleNotes)
        return s + "\n"
    }

    private static func overviewSection(_ r: HealthReport) -> String {
        var s = "## Tổng quan\n"
        s += "- Đánh giá chung: **\(r.overallLevel.label)** — \(r.overallText)\n"
        for st in r.stats {
            var line = "- \(st.title): **\(st.value) \(st.unit)** (\(st.level.label))"
            if let d = st.delta { line += " — \(d)" }
            s += line + "\n"
        }
        return s + "\n"
    }

    private static func findingsSection(_ r: HealthReport) -> String {
        guard !r.findings.isEmpty else { return "" }
        var s = "## Nhận xét tự động (theo ngưỡng cá nhân)\n"
        for f in r.findings {
            s += "- [\(f.level.label)] **\(f.title)** — \(f.detail)\(f.isDoctor ? " (bám lời BS dặn)" : "")\n"
        }
        if !r.advice.isEmpty {
            s += "\nGợi ý của app:\n" + r.advice.map { "- \($0)" }.joined(separator: "\n") + "\n"
        }
        return s + "\n"
    }

    /// Tổng hợp theo tuần (kỳ ≥ 30 ngày) — để AI thấy xu hướng tuần này so tuần trước.
    private static func weeklySection(_ r: HealthReport) -> String {
        guard r.period.kind.days >= 30 else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
        var s = "## Theo tuần (cũ → mới)\n| Tuần | Ngủ TB | Đêm ≥ mục tiêu | Nhịp nghỉ TB | HRV TB | Bước TB | Cân cuối tuần | Rượu bia (ly/ngày) | Triệu chứng |\n|---|---|---|---|---|---|---|---|---|\n"
        let chunks = stride(from: 0, to: r.days.count, by: 7).map { Array(r.days[$0..<min($0 + 7, r.days.count)]) }
        for c in chunks {
            guard let first = c.first, let last = c.last else { continue }
            func m(_ v: [Double], _ d: Int = 1) -> String { ReportMath.mean(v).map { TodayViewModel.decimal($0, digits: d) } ?? "–" }
            let goal = c.filter { ($0.sleepHours ?? 0) >= Thresholds.sleepGoalHours }.count
            let alc = c.reduce(0.0) { $0 + $1.alcoholUnits }
            let alcDays = c.filter(\.hadAlcohol).count
            s += "| \(f.string(from: first.date))–\(f.string(from: last.date)) | \(m(c.compactMap(\.sleepHours))) | \(goal)/\(c.count) | \(m(c.compactMap(\.restingHR), 0)) | \(m(c.compactMap(\.hrv), 0)) | \(ReportMath.mean(c.compactMap { $0.steps.map(Double.init) }).map { TodayViewModel.grouped(Int($0.rounded())) } ?? "–") | \(c.compactMap(\.weightKg).last.map { TodayViewModel.decimal($0, digits: 1) } ?? "–") | \(Int(alc.rounded()))/\(alcDays) | \(c.reduce(0) { $0 + $1.symptoms.count }) |\n"
        }
        return s + "\n"
    }

    private static func dailyTable(_ r: HealthReport) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EE d/M"
        let hasHRV = r.days.contains { $0.hrv != nil }
        let hasOxy = r.days.contains { $0.oxygen != nil || $0.respiratoryRate != nil }
        var head = ["Ngày", "Ngủ (giờ)", "Đi ngủ→dậy", "Thức", "Nhịp nghỉ", "Tim thấp–cao"]
        if hasHRV { head.append("HRV ms") }
        if hasOxy { head += ["SpO2 %", "Nhịp thở"] }
        head += ["Bước", "Cân kg", "Rượu bia", "Ngủ trưa", "Triệu chứng"]
        var s = "## Số liệu theo ngày (giấc ngủ = đêm trước ngày đó)\n"
        s += "| " + head.joined(separator: " | ") + " |\n"
        s += "|" + head.map { _ in "---" }.joined(separator: "|") + "|\n"
        func v(_ d: Double?, _ digits: Int = 1) -> String { d.map { TodayViewModel.decimal($0, digits: digits) } ?? "–" }
        for d in r.days {
            var row = [f.string(from: d.date), v(d.sleepHours)]
            row.append(d.bedTime != nil && d.wakeTime != nil ? "\(TodayViewModel.time(d.bedTime!))→\(TodayViewModel.time(d.wakeTime!))" : "–")
            row.append(d.awakeCount.map { "\($0)" } ?? "–")
            row.append(v(d.restingHR, 0))
            row.append(d.heartMin != nil && d.heartMax != nil ? "\(Int(d.heartMin!.rounded()))–\(Int(d.heartMax!.rounded()))" : "–")
            if hasHRV { row.append(v(d.hrv, 0)) }
            if hasOxy { row += [v(d.oxygen, 0), v(d.respiratoryRate, 1)] }
            row.append(d.steps.map { TodayViewModel.grouped($0) } ?? "–")
            row.append(v(d.weightKg))
            row.append(d.hadAlcohol ? "\(Int(d.alcoholUnits.rounded())) ly" + (d.alcoholLatest.map { " (\(TodayViewModel.time($0)))" } ?? "") : "–")
            row.append(d.napCount > 0 ? "\(d.napCount)×\(d.napMinutes / d.napCount)'" : "–")
            row.append(d.symptoms.isEmpty ? "–" : d.symptoms.joined(separator: ", ") + (d.symptomTimes.isEmpty ? "" : " (\(d.symptomTimes.joined(separator: ", ")))"))
            s += "| " + row.joined(separator: " | ") + " |\n"
        }
        return s + "\n"
    }

    /// Giai đoạn từng đêm từ ngày `from` (cho công cụ AI).
    static func nights(_ r: HealthReport, from: Date) -> String {
        let filtered = HealthReport(period: r.period, generatedAt: r.generatedAt, profile: r.profile, sourceTitle: r.sourceTitle,
                                    isMock: r.isMock, days: r.days.filter { $0.date >= from }, previousDays: [], stats: [],
                                    findings: [], advice: [], overallLevel: .unknown, overallText: "")
        let s = nightsSection(filtered)
        return s.isEmpty ? "Không có giai đoạn ngủ trong khoảng này (nguồn chưa ghi chi tiết)." : s
    }

    /// Giai đoạn từng đêm (chỉ khi kỳ có nạp chi tiết).
    private static func nightsSection(_ r: HealthReport) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EE d/M"
        let nights = r.days.filter { $0.deepMinutes != nil }
        guard !nights.isEmpty else { return "" }
        var s = "## Giai đoạn ngủ từng đêm (đêm trước ngày ghi)\n"
        s += "| Ngày | Đi ngủ→dậy | Ngủ (giờ) | Sâu | REM | Nông | Thức (phút) | Thiu thiu | Các lần thức ≥5' |\n|---|---|---|---|---|---|---|---|---|\n"
        for d in nights {
            let total = (d.sleepHours ?? 0) * 60
            func pct(_ m: Double?) -> String { guard let m, total > 0 else { return "–" }; return "\(Int(m.rounded()))' (\(Int((m / total * 100).rounded()))%)" }
            let bw = d.bedTime != nil && d.wakeTime != nil ? "\(TodayViewModel.time(d.bedTime!))→\(TodayViewModel.time(d.wakeTime!))" : "–"
            s += "| \(f.string(from: d.date)) | \(bw) | \(TodayViewModel.decimal(d.sleepHours ?? 0, digits: 1)) | \(pct(d.deepMinutes)) | \(pct(d.remMinutes)) | \(pct(d.lightMinutes)) | \(Int((d.awakeMinutes ?? 0).rounded())) | \(d.latencyMinutes.map { "\(Int($0.rounded()))'" } ?? "–") | \(d.awakeEpisodes.isEmpty ? "không" : d.awakeEpisodes.joined(separator: ", ")) |\n"
        }
        return s + "\n"
    }

    /// Nhịp tim theo giờ (TB mỗi giờ, kèm thấp–cao) — chỉ kỳ ngắn.
    private static func heartHourlySection(_ r: HealthReport) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EE d/M"
        let days = r.days.filter { !$0.hourlyHR.isEmpty }
        guard !days.isEmpty else { return "" }
        var s = "## Nhịp tim theo giờ (giờ: trung bình [thấp–cao])\n"
        for d in days {
            let parts = d.hourlyHR.map { "\($0.hour)h: \($0.avg) [\($0.lo)–\($0.hi)]" }
            s += "- **\(f.string(from: d.date))**: " + parts.joined(separator: " · ") + "\n"
        }
        return s + "\n"
    }

    private static func diarySection(_ r: HealthReport) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEE d/M"
        var lines: [String] = []
        for d in r.days {
            var parts: [String] = []
            if !d.meals.isEmpty { parts.append("Bữa ăn: " + d.meals.joined(separator: "; ")) }
            if !d.heartEvents.isEmpty { parts.append("Sự kiện nhịp tim: " + d.heartEvents.joined(separator: "; ")) }
            if d.breathingSessions > 0 {
                let drops = d.breathingDrops.map { "\($0 >= 0 ? "hạ" : "tăng") \(abs($0))" }.joined(separator: ", ")
                parts.append("Bài thở: \(d.breathingSessions) lần" + (drops.isEmpty ? "" : " (\(drops) nhịp)"))
            }
            if let t = d.skinTemp { parts.append("Nhiệt độ da \(t >= 0 ? "+" : "−")\(TodayViewModel.decimal(abs(t), digits: 1)) °C so nền") }
            if let a = d.activeHours { parts.append("Giờ có vận động \(a)/9") }
            if let km = d.distanceKm { parts.append("Quãng đường \(TodayViewModel.decimal(km, digits: 1)) km") }
            if !parts.isEmpty { lines.append("- **\(f.string(from: d.date))**: " + parts.joined(separator: " · ")) }
        }
        guard !lines.isEmpty else { return "" }
        return "## Nhật ký & chi tiết thêm\n" + lines.joined(separator: "\n") + "\n"
    }
}

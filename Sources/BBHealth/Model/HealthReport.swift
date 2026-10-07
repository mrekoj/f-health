import Foundation

/// Loại báo cáo: 1 ngày · 7 ngày · 30 ngày (tính lùi từ ngày chọn, giống màn Xu hướng).
enum ReportKind: String, CaseIterable, Identifiable, Codable {
    case day, week, month, quarter
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Ngày"
        case .week: return "Tuần"
        case .month: return "Tháng"
        case .quarter: return "90 ngày"
        }
    }
    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        }
    }
    /// Kỳ ngắn: nạp cả giai đoạn ngủ + nhịp tim theo giờ từng ngày (kỳ dài để AI tự hỏi qua công cụ).
    var loadsDetail: Bool { days <= 7 }
    /// Số ngày của kỳ so sánh (ngày: so với TB 7 ngày trước; tuần/tháng: kỳ trước cùng độ dài).
    var comparisonDays: Int { self == .day ? 7 : days }
}

/// Khoảng thời gian của báo cáo: `kind` + ngày cuối (đầu ngày).
struct ReportPeriod: Equatable, Hashable {
    let kind: ReportKind
    let end: Date

    init(kind: ReportKind, end: Date) {
        self.kind = kind
        self.end = Calendar.current.startOfDay(for: end)
    }

    var start: Date { Calendar.current.date(byAdding: .day, value: -(kind.days - 1), to: end) ?? end }
    var previousEnd: Date { Calendar.current.date(byAdding: .day, value: -1, to: start) ?? start }
    var previousStart: Date {
        Calendar.current.date(byAdding: .day, value: -(kind.comparisonDays - 1), to: previousEnd) ?? previousEnd
    }

    /// "Thứ Bảy, 4/10" · "7 ngày đến 4/10" · "30 ngày đến 4/10"
    var title: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        switch kind {
        case .day:
            if Calendar.current.isDateInToday(end) { return "Hôm nay" }
            if Calendar.current.isDateInYesterday(end) { return "Hôm qua" }
            f.dateFormat = "EEEE, d/M"
            let s = f.string(from: end)
            return s.prefix(1).uppercased() + s.dropFirst()
        case .week, .month, .quarter:
            f.dateFormat = "d/M"
            return "\(kind.days) ngày đến \(f.string(from: end))"
        }
    }

    /// "04/10/2026" hoặc "28/09 → 04/10/2026" — cho tiêu đề gói văn bản.
    var rangeText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "dd/MM/yyyy"
        if kind == .day { return f.string(from: end) }
        let s = DateFormatter()
        s.locale = f.locale
        s.dateFormat = "dd/MM"
        return "\(s.string(from: start)) → \(f.string(from: end))"
    }

    func shifted(by delta: Int) -> ReportPeriod {
        ReportPeriod(kind: kind, end: Calendar.current.date(byAdding: .day, value: delta * kind.days, to: end) ?? end)
    }
}

/// Số liệu **một ngày** trong báo cáo (đêm trước + ban ngày + nhật ký ghi tay).
struct ReportDay: Identifiable {
    let date: Date
    var id: Date { date }

    // Đêm trước ngày `date`
    var sleepHours: Double?
    var bedTime: Date?
    var wakeTime: Date?
    var awakeCount: Int?
    var hrv: Double?
    var skinTemp: Double?
    var respiratoryRate: Double?
    var oxygen: Double?
    /// Giai đoạn ngủ (phút) — chỉ nạp cho kỳ ngày/tuần (T-030).
    var deepMinutes: Double?
    var remMinutes: Double?
    var lightMinutes: Double?
    var awakeMinutes: Double?
    /// Các lần thức ≥ 5 phút giữa đêm: "02:10 (25')".
    var awakeEpisodes: [String] = []
    /// Phút để thiu thiu.
    var latencyMinutes: Double?
    // Trong ngày
    var restingHR: Double?
    var heartMin: Double?
    var heartMax: Double?
    var steps: Int?
    var distanceKm: Double?
    var activeHours: Int?
    var weightKg: Double?
    /// Nhịp tim trung bình từng giờ (giờ → bpm) — chỉ kỳ ngày/tuần.
    var hourlyHR: [(hour: Int, lo: Int, avg: Int, hi: Int)] = []
    // Nhật ký
    var alcoholUnits: Double = 0
    var alcoholLatest: Date?
    /// "07:10 Bữa sáng: Phở gà" (có giờ để AI/quy tắc biết bữa muộn).
    var meals: [String] = []
    /// Phút trong ngày của bữa ăn cuối (để xét "ăn tối muộn").
    var lastMealMinute: Int?
    var symptoms: [String] = []
    var symptomTimes: [String] = []
    var napMinutes: Int = 0
    var napCount: Int = 0
    var napLateCount: Int = 0
    var breathingSessions: Int = 0
    /// Nhịp tim hạ được qua mỗi bài thở (đầu − cuối, lần/phút).
    var breathingDrops: [Int] = []
    var heartEvents: [String] = []

    var hadAlcohol: Bool { alcoholUnits > 0 }
    /// Bữa cuối sau 20h.
    var lateDinner: Bool { (lastMealMinute ?? 0) >= 20 * 60 }
    var isWeekend: Bool { [1, 7].contains(Calendar.current.component(.weekday, from: date)) }
    /// Dậy trước 5h30.
    var earlyWake: Bool {
        guard let w = wakeTime else { return false }
        let c = Calendar.current.dateComponents([.hour, .minute], from: w)
        return (c.hour ?? 9) * 60 + (c.minute ?? 0) < 5 * 60 + 30
    }
}

/// Một ô số tổng hợp trong báo cáo (vd "Ngủ trung bình 6,4 giờ").
struct ReportStat: Identifiable {
    let id: String
    let title: String
    let value: String
    let unit: String
    let level: MetricLevel
    /// "▲ 0,4 so kỳ trước" / "ngang kỳ trước" / nil.
    let delta: String?
    let symbol: String
}

/// Một nhận xét tự động theo ngưỡng cá nhân.
struct ReportFinding: Identifiable {
    let id: String
    let level: MetricLevel
    let title: String
    let detail: String
    /// Việc nên làm rút ra từ nhận xét này (nil nếu chỉ là ghi nhận tốt).
    let advice: String?
    /// true = bám lời BS dặn trong hồ sơ.
    let isDoctor: Bool
}

/// **Báo cáo sức khoẻ** cho một kỳ — vừa hiển thị trong app, vừa là gói dữ liệu gửi AI (T-025).
struct HealthReport {
    let period: ReportPeriod
    let generatedAt: Date
    let profile: HealthProfile
    /// Tên nguồn dữ liệu ("Google Health", "Ứng dụng Sức khoẻ (Apple)").
    let sourceTitle: String
    let isMock: Bool
    /// Các ngày trong kỳ (cũ → mới).
    let days: [ReportDay]
    /// Kỳ so sánh (cũ → mới), chỉ số chính.
    let previousDays: [ReportDay]
    let stats: [ReportStat]
    let findings: [ReportFinding]
    let advice: [String]
    let overallLevel: MetricLevel
    let overallText: String

    var hasAnyData: Bool {
        days.contains { $0.sleepHours != nil || $0.restingHR != nil || $0.steps != nil || $0.weightKg != nil }
    }
}

// MARK: - Thống kê nhỏ dùng chung

enum ReportMath {
    /// Các ngày (đầu ngày) từ `from` tới `to`, kể cả hai đầu.
    static func days(from: Date, to: Date) -> [Date] {
        let cal = Calendar.current
        var d = cal.startOfDay(for: from)
        let end = cal.startOfDay(for: to)
        var out: [Date] = []
        while d <= end {
            out.append(d)
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return out
    }
    static func mean(_ v: [Double]) -> Double? {
        guard !v.isEmpty else { return nil }
        return v.reduce(0, +) / Double(v.count)
    }
    static func stdev(_ v: [Double]) -> Double? {
        guard v.count >= 2, let m = mean(v) else { return nil }
        return (v.map { ($0 - m) * ($0 - m) }.reduce(0, +) / Double(v.count)).squareRoot()
    }
    /// Phút trong ngày của giờ đi ngủ, quy về cùng trục (giờ sau 0h cộng 24h) để tính TB/độ lệch.
    static func bedMinute(_ d: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        if m < 12 * 60 { m += 24 * 60 }
        return m
    }
    static func minuteText(_ m: Double) -> String {
        let total = Int(m.rounded()) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
    /// "▲ 0,4 so kỳ trước" / "▼ 3 so kỳ trước" / "ngang kỳ trước".
    static func deltaText(_ d: Double, digits: Int, suffix: String = "so kỳ trước") -> String {
        let eps = digits == 0 ? 0.5 : 0.05
        if abs(d) < eps { return "ngang \(suffix)" }
        let arrow = d > 0 ? "▲" : "▼"
        return "\(arrow) \(TodayViewModel.decimal(abs(d), digits: digits)) \(suffix)"
    }
}

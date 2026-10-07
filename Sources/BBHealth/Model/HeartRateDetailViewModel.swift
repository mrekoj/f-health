import Foundation
import Observation

/// Chế độ xem màn Nhịp tim chi tiết (kiểu Google Health): theo ngày / theo tuần / theo tháng.
enum HeartMode: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: return "Ngày"
        case .week: return "Tuần"
        case .month: return "Tháng"
        }
    }

    static func from(_ raw: String) -> HeartMode { HeartMode(rawValue: raw) ?? .day }
}

/// Dữ liệu màn Nhịp tim chi tiết.
/// - Ngày: nhịp tim theo giờ (intraday) đầy đủ của ngày đang chọn + HRV + đánh giá.
/// - Tuần: dải thấp–cao mỗi ngày (7 ngày) + chấm nhịp tim nghỉ.
/// - Tháng: dải thấp–cao 30 ngày gần nhất (trục ngày thưa).
@Observable
@MainActor
final class HeartRateDetailViewModel {
    enum State: Equatable { case idle, loading, loaded, empty, failed(String) }

    private(set) var state: State = .idle

    /// Chế độ đang xem (đổi trên segmented ở đầu màn).
    var mode: HeartMode

    // MARK: - Chế độ Ngày
    /// Ngày đang xem (đầu ngày); mặc định hôm nay, lùi/tiến được nhưng không quá hôm nay.
    var selectedDay: Date
    private(set) var dayDetail: HeartRateDetail?

    // MARK: - Chế độ Tuần/Tháng
    /// Một ngày bất kỳ trong tuần đang hiển thị (để tính mốc đầu tuần).
    var weekAnchor: Date
    private(set) var weekRanges: [HeartDayRange] = []
    private(set) var monthRanges: [HeartDayRange] = []

    /// Mốc "hôm nay" của màn (trần không cho đi tới tương lai).
    let today: Date
    private let source: HealthSource
    private let providerOverride: (any HealthStoreProvider)?
    private let cal = Calendar.current

    init(date: Date, mode: HeartMode? = nil, providerOverride: (any HealthStoreProvider)? = nil) {
        let start = Calendar.current.startOfDay(for: date)
        self.today = start
        self.selectedDay = start
        self.weekAnchor = start
        self.mode = mode ?? .from(DebugOptions.heartMode)
        self.providerOverride = providerOverride
        self.source = AppSettings.shared.source
    }

    private func provider() -> any HealthStoreProvider {
        providerOverride ?? HealthStoreFactory.make(for: source)
    }

    /// Nguồn có dùng dữ liệu Google không (để quyết hiện khối HRV).
    var usesGoogle: Bool { source.usesGoogle }

    // MARK: - Mốc thời gian

    var dayStart: Date { selectedDay }
    var dayEnd: Date { cal.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay }

    /// Đầu tuần (theo lịch máy) của tuần đang hiển thị.
    var weekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: weekAnchor)?.start ?? cal.startOfDay(for: weekAnchor)
    }
    /// 7 ngày của tuần đang hiển thị.
    var weekDays: [Date] {
        (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
    }
    private var currentWeekStart: Date {
        cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
    }

    // MARK: - Điều hướng

    var canGoNextDay: Bool { selectedDay < today }
    func goPrevDay() { selectedDay = cal.date(byAdding: .day, value: -1, to: selectedDay) ?? selectedDay }
    func goNextDay() { if canGoNextDay { selectedDay = cal.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay } }

    var canGoNextWeek: Bool { weekStart < currentWeekStart }
    func goPrevWeek() { weekAnchor = cal.date(byAdding: .day, value: -7, to: weekAnchor) ?? weekAnchor }
    func goNextWeek() { if canGoNextWeek { weekAnchor = cal.date(byAdding: .day, value: 7, to: weekAnchor) ?? weekAnchor } }

    /// Chạm 1 ngày ở Tuần/Tháng → sang chế độ Ngày của ngày đó.
    func showDay(_ date: Date) {
        selectedDay = cal.startOfDay(for: date)
        mode = .day
    }

    // MARK: - Nạp dữ liệu

    func load() async {
        state = .loading
        let provider = provider()
        do {
            switch mode {
            case .day:   try await loadDay(provider)
            case .week:  try await loadWeek(provider)
            case .month: try await loadMonth(provider)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func loadDay(_ provider: any HealthStoreProvider) async throws {
        async let r = provider.restingHeartRate(for: selectedDay)
        async let i = provider.intradayHeartRate(for: selectedDay)
        async let v = provider.heartRateVariability(for: selectedDay)
        let (resting, intradayRaw, hrvToday) = try await (r, i, v)
        let points = (intradayRaw ?? []).map { HeartRatePoint(time: $0.time, bpm: $0.bpm) }
        dayDetail = HeartRateDetail(restingBpm: resting, intraday: points, hrv: hrvToday)
        state = (resting == nil && points.isEmpty) ? .empty : .loaded
    }

    private func loadWeek(_ provider: any HealthStoreProvider) async throws {
        let end = min(weekDays.last ?? weekStart, today)
        let ranges = try await provider.heartRateDailyRanges(from: weekStart, to: end)
        weekRanges = ranges.map { HeartDayRange(date: $0.date, min: $0.min, max: $0.max, resting: $0.resting) }
        state = weekRanges.isEmpty ? .empty : .loaded
    }

    private func loadMonth(_ provider: any HealthStoreProvider) async throws {
        let from = cal.date(byAdding: .day, value: -29, to: today) ?? today
        let ranges = try await provider.heartRateDailyRanges(from: from, to: today)
        monthRanges = ranges.map { HeartDayRange(date: $0.date, min: $0.min, max: $0.max, resting: $0.resting) }
        state = monthRanges.isEmpty ? .empty : .loaded
    }

    // MARK: - Tiện ích cho biểu đồ Ngày

    /// Nhịp tim gần nhất với thời điểm `time` (để hiện callout khi chạm/quét biểu đồ).
    func bpm(at time: Date) -> Double? {
        dayDetail?.intraday.min(by: {
            abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time))
        })?.bpm
    }

    // MARK: - Câu kết luận lớn (chế độ Ngày)

    var headline: String {
        guard let d = dayDetail, let bpm = d.restingBpm else {
            return "Chưa có số nhịp tim nghỉ ngày này."
        }
        let n = Int(bpm.rounded())
        switch Thresholds.restingHeartRate(bpm: bpm) {
        case .good: return "Nhịp tim nghỉ \(n) lần/phút — nằm trong vùng tốt. Cơ thể đang được nghỉ ngơi ổn."
        case .caution: return "Nhịp tim nghỉ \(n) lần/phút — hơi cao hơn mức tốt. Xem lại giấc ngủ và rượu bia tối qua."
        default: return "Nhịp tim nghỉ \(n) lần/phút — cao. Nghỉ ngơi, uống đủ nước; nếu kéo dài kèm mệt thì đi khám."
        }
    }

    /// Mô tả cao nhất/thấp nhất trong ngày (nếu có intraday).
    var rangeText: String? {
        guard let d = dayDetail, d.hasIntraday, let lo = d.minBpm, let hi = d.maxBpm else { return nil }
        return "Trong ngày: thấp nhất \(Int(lo.rounded())) · cao nhất \(Int(hi.rounded())) lần/phút"
    }

    var hrvValueText: String {
        guard let v = dayDetail?.hrv else { return "—" }
        return "\(Int(v.rounded()))"
    }

    // MARK: - Tóm tắt Tuần/Tháng

    /// Nhịp tim nghỉ trung bình của dải đang xem (Tuần/Tháng).
    func averageResting(_ ranges: [HeartDayRange]) -> Double? {
        let vals = ranges.compactMap(\.resting)
        guard !vals.isEmpty else { return nil }
        return vals.reduce(0, +) / Double(vals.count)
    }
}

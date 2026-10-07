import Foundation
import Observation

/// Một điểm dữ liệu ngày cho biểu đồ.
struct DayValue: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct SleepDay: Identifiable {
    let date: Date
    let summary: SleepSummary
    var id: Date { date }
    var hours: Double { summary.totalHours }
    var level: MetricLevel { Thresholds.sleep(hours: summary.totalHours) }
}

/// Dữ liệu màn Xu hướng: tải 2×N ngày để vừa vẽ N ngày, vừa so trung bình với N ngày trước.
@Observable
@MainActor
final class TrendsViewModel {
    enum State: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var state: State = .idle
    /// Số ngày hiển thị: 7 hoặc 30.
    var range: Int = 7

    private var allSleep: [SleepDay] = []
    private var allRHR: [DayValue] = []
    private var allSteps: [DayValue] = []
    private var allWeight: [DayValue] = []
    private var allHRV: [DayValue] = []
    private var allSkin: [DayValue] = []
    private var allDistance: [DayValue] = []
    private var allActiveHours: [DayValue] = []

    let today: Date
    private let providerOverride: (any HealthStoreProvider)?

    init(providerOverride: (any HealthStoreProvider)? = nil, today: Date = Date(), range: Int = 7) {
        self.providerOverride = providerOverride
        self.today = Calendar.current.startOfDay(for: today)
        self.range = range
    }

    private func provider() -> any HealthStoreProvider {
        providerOverride ?? HealthStoreFactory.make(for: AppSettings.shared.source)
    }

    // Chuỗi hiển thị (N ngày gần nhất).
    var sleep: [SleepDay] { Array(allSleep.suffix(range)) }
    var rhr: [DayValue] { Array(allRHR.suffix(range)) }
    var steps: [DayValue] { Array(allSteps.suffix(range)) }
    var weight: [DayValue] { allWeight.filter { $0.date >= windowStart } }
    /// HRV + nhiệt độ da chỉ có ở nguồn Google → rỗng với nguồn Apple (UI tự ẩn).
    var hrv: [DayValue] { allHRV.filter { $0.date >= windowStart } }
    var skinTemp: [DayValue] { allSkin.filter { $0.date >= windowStart } }
    /// T-020: quãng đường (km) và giờ vận động (số giờ ≥ 250 bước) — rỗng thì UI ẩn.
    var distance: [DayValue] { allDistance.filter { $0.date >= windowStart } }
    var activeHours: [DayValue] { allActiveHours.filter { $0.date >= windowStart } }

    private var windowStart: Date {
        Calendar.current.date(byAdding: .day, value: -(range - 1), to: today) ?? today
    }

    func load() async {
        state = .loading
        let provider = provider()
        let span = range * 2
        guard let from = Calendar.current.date(byAdding: .day, value: -(span - 1), to: today) else { return }
        do {
            async let s = provider.sleepSummaries(from: from, to: today)
            async let h = provider.restingHeartRates(from: from, to: today)
            async let st = provider.stepsSeries(from: from, to: today)
            async let w = provider.bodyMasses(from: from, to: today)
            let (sl, hr, sp, wt) = try await (s, h, st, w)
            allSleep = sl.map { SleepDay(date: $0.date, summary: $0.summary) }
            allRHR = hr.map { DayValue(date: $0.date, value: $0.bpm) }
            allSteps = sp.map { DayValue(date: $0.date, value: Double($0.steps)) }
            allWeight = wt.map { DayValue(date: $0.date, value: $0.kg) }

            // HRV + nhiệt độ da: chỉ tải khi nguồn có Google (tránh lặp gọi vô ích với Apple).
            if AppSettings.shared.source.usesGoogle {
                async let v = provider.heartRateVariabilities(from: windowStart, to: today)
                async let t = provider.skinTemperatures(from: windowStart, to: today)
                let (hrvs, skins) = try await (v, t)
                allHRV = hrvs.map { DayValue(date: $0.date, value: $0.ms) }
                allSkin = skins.map { DayValue(date: $0.date, value: $0.delta) }
            } else {
                allHRV = []; allSkin = []
            }
            // T-020: chỉ tải đúng N ngày đang xem; lỗi thì bỏ qua (biểu đồ tự ẩn).
            async let d = provider.distanceSeries(from: windowStart, to: today)
            async let ah = provider.activeHoursSeries(from: windowStart, to: today)
            allDistance = ((try? await d) ?? []).map { DayValue(date: $0.date, value: $0.km) }
            allActiveHours = ((try? await ah) ?? []).map { DayValue(date: $0.date, value: Double($0.hours)) }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Trung bình N ngày vs N ngày trước

    /// (trung bình gần đây, chênh so với kỳ trước) cho một chuỗi.
    private func avgDelta(_ values: [DayValue]) -> (avg: Double, delta: Double)? {
        let recent = values.suffix(range).map(\.value)
        let prev = values.dropLast(range).suffix(range).map(\.value)
        guard !recent.isEmpty else { return nil }
        let a = recent.reduce(0, +) / Double(recent.count)
        guard !prev.isEmpty else { return (a, 0) }
        let p = prev.reduce(0, +) / Double(prev.count)
        return (a, a - p)
    }

    var sleepAvgDelta: (avg: Double, delta: Double)? {
        avgDelta(allSleep.map { DayValue(date: $0.date, value: $0.hours) })
    }
    var rhrAvgDelta: (avg: Double, delta: Double)? { avgDelta(allRHR) }
    var stepsAvgDelta: (avg: Double, delta: Double)? { avgDelta(allSteps) }

    /// Câu tóm tắt tiếng Việt cho giấc ngủ.
    var sleepSummaryText: String? {
        guard let s = sleepAvgDelta else { return nil }
        let avg = TodayViewModel.decimal(s.avg, digits: 1)
        let period = range == 7 ? "tuần trước" : "kỳ trước"
        if abs(s.delta) < 0.05 {
            return "Ngủ trung bình \(avg) giờ/đêm — ngang \(period)."
        }
        let dir = s.delta > 0 ? "nhiều hơn" : "ít hơn"
        let diff = TodayViewModel.decimal(abs(s.delta), digits: 1)
        return "Ngủ trung bình \(avg) giờ/đêm, \(dir) \(period) \(diff) giờ."
    }

    var goodSleepNights: Int { sleep.filter { $0.hours >= Thresholds.sleepGoalHours }.count }
}

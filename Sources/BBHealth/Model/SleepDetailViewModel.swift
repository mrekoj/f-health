import Foundation
import Observation

/// Dữ liệu màn Giấc ngủ chi tiết: hypnogram đêm được chọn + bối cảnh "Tuần này".
@Observable
@MainActor
final class SleepDetailViewModel {
    enum State: Equatable { case idle, loading, loaded, empty, failed(String) }

    private(set) var state: State = .idle
    private(set) var detail: SleepDetail?
    private(set) var week: [(date: Date, detail: SleepDetail)] = []

    let date: Date
    private let providerOverride: (any HealthStoreProvider)?

    init(date: Date, providerOverride: (any HealthStoreProvider)? = nil) {
        self.date = Calendar.current.startOfDay(for: date)
        self.providerOverride = providerOverride
    }

    private func provider() -> any HealthStoreProvider {
        providerOverride ?? HealthStoreFactory.make(for: AppSettings.shared.source)
    }

    func load() async {
        guard state == .idle else { return }
        state = .loading
        let provider = provider()
        do {
            guard let d = try await provider.sleepDetail(for: date), !d.segments.isEmpty else {
                state = .empty; return
            }
            detail = d
            // 7 đêm gần nhất (tính cả đêm đang xem) cho mục "Tuần này".
            var w: [(Date, SleepDetail)] = []
            for back in 0..<7 {
                guard let day = Calendar.current.date(byAdding: .day, value: -back, to: date) else { continue }
                if let wd = try? await provider.sleepDetail(for: day), !wd.segments.isEmpty {
                    w.append((day, wd))
                }
            }
            week = w.sorted { $0.0 < $1.0 }
            state = .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Tuần này

    /// Giờ đi ngủ quy về phút quanh nửa đêm (22:30 → −90, 00:30 → +30).
    private func bedMinutes(_ d: SleepDetail) -> Double? {
        guard let b = d.bedTime else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: b)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return h >= 18 ? Double((h - 24) * 60 + m) : Double(h * 60 + m)
    }

    var avgBedtimeText: String? {
        let mins = week.compactMap { bedMinutes($0.detail) }
        guard !mins.isEmpty else { return nil }
        let avg = mins.reduce(0, +) / Double(mins.count)
        let total = (Int(avg.rounded()) + 24 * 60) % (24 * 60)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    var bedtimeStdevMin: Double? {
        let mins = week.compactMap { bedMinutes($0.detail) }
        guard mins.count >= 2 else { return nil }
        let avg = mins.reduce(0, +) / Double(mins.count)
        let variance = mins.reduce(0) { $0 + pow($1 - avg, 2) } / Double(mins.count)
        return variance.squareRoot()
    }

    var bestNight: (date: Date, hours: Double)? {
        week.max(by: { $0.detail.asleepHours < $1.detail.asleepHours })
            .map { ($0.date, $0.detail.asleepHours) }
    }
    var worstNight: (date: Date, hours: Double)? {
        week.min(by: { $0.detail.asleepHours < $1.detail.asleepHours })
            .map { ($0.date, $0.detail.asleepHours) }
    }

    var avgDeepPercent: Double? {
        guard !week.isEmpty else { return nil }
        return week.map { $0.detail.percent(of: .deep) }.reduce(0, +) / Double(week.count)
    }
    var avgRemPercent: Double? {
        guard !week.isEmpty else { return nil }
        return week.map { $0.detail.percent(of: .rem) }.reduce(0, +) / Double(week.count)
    }

    /// "Đêm qua" nếu đang xem đêm mới nhất, ngược lại "Đêm d/M" cho các đêm xem lại.
    private var nightPhrase: String {
        if Calendar.current.isDateInToday(date) { return "Đêm qua" }
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
        return "Đêm \(f.string(from: date))"
    }

    /// 1 câu kết luận lớn cho đầu màn.
    var headline: String {
        guard let d = detail else { return "Chưa có dữ liệu giấc ngủ cho đêm này." }
        let h = TodayViewModel.decimal(d.asleepHours, digits: 1)
        let when = nightPhrase
        switch Thresholds.sleep(hours: d.asleepHours) {
        case .good: return "\(when) anh ngủ \(h) giờ — đủ giấc. Giữ nếp này nhé."
        case .caution: return "\(when) anh ngủ \(h) giờ — hơi thiếu so với mục tiêu 7 giờ."
        default: return "\(when) anh ngủ \(h) giờ — còn ít, cần ưu tiên ngủ sớm hơn."
        }
    }
}

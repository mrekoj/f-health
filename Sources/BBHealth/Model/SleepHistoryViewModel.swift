import Foundation
import Observation

/// Một đêm trong danh sách **Lịch sử giấc ngủ** (tóm tắt, chạm vào để xem chi tiết).
struct SleepNight: Identifiable {
    /// Ngày thức dậy của đêm (giống cách màn Xu hướng đánh mốc đêm).
    let date: Date
    let summary: SleepSummary
    var id: Date { date }
    var hours: Double { summary.totalHours }
    var level: MetricLevel { Thresholds.sleep(hours: summary.totalHours) }
}

/// Dữ liệu màn **Lịch sử giấc ngủ**: tóm tắt nhiều đêm gần đây để anh lật lại.
/// Dùng lại `sleepSummaries(from:to:)` đã có sẵn ở mọi nguồn dữ liệu.
@Observable
@MainActor
final class SleepHistoryViewModel {
    enum State: Equatable { case idle, loading, loaded, empty, failed(String) }

    private(set) var state: State = .idle
    /// Mới nhất nằm trên đầu.
    private(set) var nights: [SleepNight] = []

    /// Số đêm xem lại: 14 hoặc 30.
    var nightCount: Int

    let today: Date
    private let providerOverride: (any HealthStoreProvider)?

    init(today: Date = Date(), nightCount: Int = 14, providerOverride: (any HealthStoreProvider)? = nil) {
        self.today = Calendar.current.startOfDay(for: today)
        self.nightCount = nightCount
        self.providerOverride = providerOverride
    }

    private func provider() -> any HealthStoreProvider {
        providerOverride ?? HealthStoreFactory.make(for: AppSettings.shared.source)
    }

    /// Tải lần đầu.
    func load() async {
        guard state == .idle else { return }
        await fetch()
    }

    /// Tải lại khi đổi số đêm hoặc đổi nguồn dữ liệu.
    func reload() async { await fetch() }

    private func fetch() async {
        state = .loading
        let provider = provider()
        guard let from = Calendar.current.date(byAdding: .day, value: -(nightCount - 1), to: today) else {
            state = .empty; return
        }
        do {
            let rows = try await provider.sleepSummaries(from: from, to: today)
            let list = rows
                .filter { $0.summary.totalHours > 0 }
                .map { SleepNight(date: $0.date, summary: $0.summary) }
                .sorted { $0.date > $1.date }   // mới nhất trên đầu
            nights = list
            state = list.isEmpty ? .empty : .loaded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Tóm tắt đầu màn

    /// Số đêm ngủ đủ 7 giờ.
    var goodNights: Int { nights.filter { $0.level == .good }.count }

    /// Số giờ ngủ trung bình các đêm có dữ liệu.
    var avgHours: Double? {
        guard !nights.isEmpty else { return nil }
        return nights.map(\.summary.totalHours).reduce(0, +) / Double(nights.count)
    }
}

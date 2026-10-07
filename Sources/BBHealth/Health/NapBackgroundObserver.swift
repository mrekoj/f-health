import Foundation
import SwiftData

/// Đăng ký theo dõi nền giấc ngủ (nguồn **Apple/HealthKit**): khi vòng Fitbit → Apple Health ghi
/// phiên ngủ mới, iOS đánh thức app nền → tự quét + lưu giấc trưa vào SwiftData.
///
/// Chỉ chạy trên iPhone thật (nguồn Apple thật). Trên simulator/`BBH_MOCK` dùng số giả nên bỏ qua —
/// đường chính khi đó là quét lúc app vào foreground (xem `BBHealthApp`). Best-effort, bọc guard.
@MainActor
final class NapBackgroundObserver {
    static let shared = NapBackgroundObserver()

    private var started = false
    private var container: ModelContainer?

    /// Gọi 1 lần khi app khởi động.
    func start(container: ModelContainer) {
        guard !started else { return }
        self.container = container
        // Trên máy ảo/số giả không có HealthKit thật → chỉ dựa vào quét foreground.
        guard !HealthStoreFactory.useMock else { return }
        started = true

        let provider = HKHealthStoreProvider()
        provider.startObservingSleep { [weak self] in
            // Callback nền chạy trên luồng bất kỳ → nhảy về MainActor để dùng SwiftData an toàn.
            Task { @MainActor in
                await self?.scan(using: provider)
            }
        }
    }

    private func scan(using provider: HKHealthStoreProvider) async {
        guard let container else { return }
        let context = ModelContext(container)
        await NapAutoLogger.scanAndLog(provider: provider, context: context, source: "Sức khoẻ")
    }
}

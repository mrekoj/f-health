import SwiftUI
import SwiftData
import UserNotifications

@main
struct BBHealthApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    init() {
        // T-033: nhận thông báo (nhắc báo cáo tuần) cả khi app đang mở và khi chạm vào thông báo.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        do {
            container = try ModelContainer(for: DailyLog.self, LogEntry.self, HeartEvent.self, NapLog.self,
                                           LiveSession.self, AIAnalysis.self, AIChatMessage.self)
        } catch {
            fatalError("Không tạo được kho dữ liệu: \(error)")
        }
        // Đăng ký theo dõi nền giấc ngủ (nguồn Apple thật) → tự lưu giấc trưa khi iOS đánh thức app.
        NapBackgroundObserver.shared.start(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.locale, Locale(identifier: "vi_VN"))
                .tint(Theme.brand)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Mỗi lần app vào foreground: quét + lưu giấc trưa gần đây (đường chính, cả Apple & Google).
            if phase == .active {
                let context = container.mainContext
                Task { @MainActor in
                    let source = AppSettings.shared.source
                    await NapAutoLogger.scanAndLog(
                        provider: HealthStoreFactory.make(for: source),
                        context: context,
                        source: NapAutoLogger.sourceLabel(for: source))
                }
            }
        }
    }
}

/// Tham số chạy thử (launch arguments) — chỉ dùng để chụp màn hình / kiểm tra giao diện.
/// Ví dụ: `-BBHShowExplain sleep` · `-BBHTab plan` · `-BBHNow 09:10`.
enum DebugOptions {
    private static var defaults: UserDefaults { .standard }

    /// Mở sẵn sheet giải thích của chỉ số (sleep/restingHeartRate/steps/bodyMass).
    static var showExplain: Metric? {
        #if DEBUG
        return defaults.string(forKey: "BBHShowExplain").flatMap(Metric.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// Tab mở đầu: today/log/trends/plan/settings.
    static var initialTab: String {
        #if DEBUG
        return defaults.string(forKey: "BBHTab") ?? "today"
        #else
        return "today"
        #endif
    }

    /// Khoảng Xu hướng mở đầu (7/30/90) — chỉ để chụp màn hình.
    static var trendsRange: Int {
        #if DEBUG
        let r = defaults.integer(forKey: "BBHRange")
        return r == 30 ? 30 : (r == 90 ? 90 : 7)
        #else
        return 7
        #endif
    }

    /// Mở sẵn sheet Nhịp tim chi tiết (chụp màn hình).
    static var showHeartDetail: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowHeart")
        #else
        return false
        #endif
    }

    /// Mở sẵn màn Nhịp tim trực tiếp từ màn Nhịp tim (dùng kèm `-BBHShowHeart YES`; chụp màn hình).
    static var showLive: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowLive")
        #else
        return false
        #endif
    }

    /// Mở sẵn bài thở (tự bắt đầu, trừ khi có `-BBHBreathLibrary YES`) từ màn Nhịp tim trực tiếp
    /// (dùng kèm `-BBHShowHeart YES -BBHShowLive YES`; chụp màn hình).
    static var showBreath: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowBreath")
        #else
        return false
        #endif
    }

    /// Chọn sẵn bài thở theo id (`slow46`, `even55`, `belly`, `sigh`, `box`, `478`, `alternate`) khi mở
    /// bằng `-BBHShowBreath YES` (T-024; chụp màn hình). Vd `-BBHBreathPattern box`.
    static var breathPattern: String? {
        #if DEBUG
        return defaults.string(forKey: "BBHBreathPattern")
        #else
        return nil
        #endif
    }

    /// Mở bài thở nhưng ở lại màn chọn bài, không tự bắt đầu (T-024; chụp màn hình thư viện).
    static var breathLibrary: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHBreathLibrary")
        #else
        return false
        #endif
    }

    /// Mở sẵn sheet Chi tiết của bài đang chọn ở màn chọn bài (T-024; dùng kèm `-BBHBreathLibrary YES`).
    static var breathDetail: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHBreathDetail")
        #else
        return false
        #endif
    }

    /// Bài thở tự kết thúc sau N giây để nhảy tới màn tóm tắt (0 = không; chụp màn hình).
    /// Vd `-BBHBreathEndAfter 12`. Trên sim, nhịp giả cũng hạ nhanh trong N giây đó.
    static var breathEndAfter: Int {
        #if DEBUG
        return max(0, defaults.integer(forKey: "BBHBreathEndAfter"))
        #else
        return 0
        #endif
    }

    /// Simulator: giả lập vòng "đầy đủ" (pin, tiếp xúc da, RR) thay vì giống Fitbit Air thật
    /// (chỉ nhịp tim + thông tin thiết bị). Chỉ để xem các hàng ẩn của khối Thông tin vòng.
    static var simFullRing: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHSimFullRing")
        #else
        return false
        #endif
    }

    /// Chế độ mở đầu của màn Nhịp tim chi tiết: day/week/month (chụp màn hình).
    static var heartMode: String {
        #if DEBUG
        return defaults.string(forKey: "BBHHeartMode") ?? "day"
        #else
        return "day"
        #endif
    }

    /// Mở sẵn màn Báo cáo (T-025) từ tab Xu hướng: `-BBHShowReport day|week|month` (chụp màn hình).
    static var showReport: ReportKind? {
        #if DEBUG
        return defaults.string(forKey: "BBHShowReport").flatMap(ReportKind.init(rawValue:))
        #else
        return nil
        #endif
    }

    /// Mở sẵn sheet "Xem nội dung sẽ gửi" trong màn Báo cáo (dùng kèm `-BBHShowReport`; chụp màn hình).
    static var showReportText: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHReportText")
        #else
        return false
        #endif
    }

    /// Màn Báo cáo tự bấm "Nhờ AI phân tích" khi kỳ chưa có bài (T-026; chụp màn/kiểm sim).
    static var autoAI: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHAutoAI")
        #else
        return false
        #endif
    }

    /// Kèm `-BBHAutoAI`: chạy Phân tích sâu thay vì nhanh (T-031).
    static var deepAI: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHDeepAI")
        #else
        return false
        #endif
    }

    /// Mở màn Hỏi AI từ Báo cáo và gửi sẵn câu hỏi: `-BBHChat "câu hỏi"` (T-027; kiểm sim).
    static var chatQuestion: String? {
        #if DEBUG
        return defaults.string(forKey: "BBHChat")
        #else
        return nil
        #endif
    }

    /// Mở sẵn màn Trợ lý AI từ tab Cài đặt (chụp màn hình).
    static var showAISettings: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowAI")
        #else
        return false
        #endif
    }

    /// Mở sẵn màn Hồ sơ của tôi từ tab Cài đặt (chụp màn hình).
    static var showProfile: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowProfile")
        #else
        return false
        #endif
    }

    /// Ép hiện màn Chào mừng (onboarding) dù hồ sơ đã có (chụp màn hình): `-BBHOnboarding YES`.
    static var showOnboarding: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHOnboarding")
        #else
        return false
        #endif
    }

    /// Mở sẵn màn Lịch sử giấc ngủ (chụp màn hình).
    static var showSleepHistory: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowHistory")
        #else
        return false
        #endif
    }

    /// Mở sẵn sheet Giấc ngủ chi tiết (chụp màn hình).
    static var showSleepDetail: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowSleep")
        #else
        return false
        #endif
    }

    /// Mở sẵn màn Giấc ngủ trưa (chụp màn hình).
    static var showNaps: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHShowNaps")
        #else
        return false
        #endif
    }

    /// Mở màn ở cuối trang (chụp màn hình phần dưới).
    static var scrollToBottom: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHScrollBottom")
        #else
        return false
        #endif
    }

    /// Nạp sẵn vài mục ghi nhanh mẫu (chỉ để chụp màn hình).
    static var seedLog: Bool {
        #if DEBUG
        return defaults.bool(forKey: "BBHSeedLog")
        #else
        return false
        #endif
    }

    /// Giờ giả lập "HH:mm" trong ngày hôm nay.
    static var now: Date {
        #if DEBUG
        if let s = defaults.string(forKey: "BBHNow") {
            let parts = s.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2,
               let d = Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date()) {
                return d
            }
        }
        #endif
        return Date()
    }
}

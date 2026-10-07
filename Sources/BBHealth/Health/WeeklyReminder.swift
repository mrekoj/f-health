import Foundation
import Observation
import UserNotifications
import UIKit

/// **Nhắc báo cáo tuần** (T-033): thông báo sáng thứ Hai 7h30 → chạm vào mở Xu hướng → Báo cáo tuần
/// (AI tự phân tích nếu đã thiết lập). Thông báo cục bộ, không máy chủ.
enum WeeklyReminder {
    static let identifier = "bbh.weekly-report"
    private static let enabledKey = "bbh.reminder.weekly"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Xin quyền (nếu cần) rồi đặt lịch lặp hằng tuần. Trả `false` nếu người dùng từ chối quyền.
    @discardableResult
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { isEnabled = false; return false }
        let content = UNMutableNotificationContent()
        content.title = "Báo cáo tuần đã sẵn sàng"
        content.body = "Xem 7 ngày qua: ngủ, nhịp tim, cân, rượu bia — và lời khuyên của AI cho tuần mới."
        content.sound = .default
        content.userInfo = ["open": "weekly-report"]
        var comps = DateComponents()
        comps.weekday = 2   // thứ Hai
        comps.hour = 7
        comps.minute = 30
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        try? await center.add(req)
        isEnabled = true
        return true
    }

    static func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        isEnabled = false
    }

    /// Mở app bằng thông báo → đánh dấu để RootTabView chuyển sang Xu hướng và mở Báo cáo tuần.
    static func handle(_ response: UNNotificationResponse) {
        guard response.notification.request.content.userInfo["open"] as? String == "weekly-report" else { return }
        Task { @MainActor in PendingNavigation.shared.openWeeklyReport = true }
    }
}

/// Điều hướng chờ xử lý (từ thông báo). RootTabView/TrendsView theo dõi và tự xoá cờ khi đã mở.
@Observable
@MainActor
final class PendingNavigation {
    static let shared = PendingNavigation()
    var openWeeklyReport = false
}

/// Nhận thông báo khi app đang mở và khi người dùng chạm vào thông báo.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        WeeklyReminder.handle(response)
    }
}

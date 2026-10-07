import Foundation
import Observation

/// Nguồn dữ liệu sức khoẻ mà người dùng chọn trong Cài đặt.
enum HealthSource: String, CaseIterable, Identifiable {
    /// Đọc từ ứng dụng Sức khoẻ của Apple (Fitbit → Google Health → Apple Health).
    case apple
    /// Gọi thẳng Google Health API v4 (đủ HRV, nhiệt độ da).
    case google
    /// Cả hai: ưu tiên Google, thiếu số thì lấy Apple.
    case both

    var id: String { rawValue }

    /// Tên hiển thị trên màn Cài đặt.
    var title: String {
        switch self {
        case .apple: return "Ứng dụng Sức khoẻ (Apple)"
        case .google: return "Google Health"
        case .both: return "Cả hai nguồn"
        }
    }

    /// Mô tả ngắn dưới tên.
    var subtitle: String {
        switch self {
        case .apple: return "Số Fitbit đã đồng bộ sang máy qua ứng dụng Sức khoẻ. Không cần đăng nhập."
        case .google: return "Gọi thẳng Google Health — có thêm biến thiên nhịp tim và nhiệt độ da."
        case .both: return "Ưu tiên Google; chỉ số nào Google thiếu thì lấy từ ứng dụng Sức khoẻ."
        }
    }

    var symbol: String {
        switch self {
        case .apple: return "heart.text.square.fill"
        case .google: return "g.circle.fill"
        case .both: return "arrow.triangle.2.circlepath"
        }
    }

    /// Nguồn này có dùng dữ liệu Google không (để quyết định hiện HRV/nhiệt độ da).
    var usesGoogle: Bool { self != .apple }
}

/// Cấu hình toàn app: nguồn dữ liệu + Google OAuth Client ID + thời điểm cập nhật gần nhất.
/// Lưu trong `UserDefaults` (máy cá nhân, không tài khoản/máy chủ).
@Observable
@MainActor
final class AppSettings {
    static let shared = AppSettings()

    private enum Keys {
        static let source = "bbh.healthSource"
        static let clientID = "bbh.googleClientID"
        static let appleUpdated = "bbh.lastUpdated.apple"
        static let googleUpdated = "bbh.lastUpdated.google"
    }

    private let defaults: UserDefaults

    var source: HealthSource {
        didSet { defaults.set(source.rawValue, forKey: Keys.source) }
    }

    /// Google OAuth Client ID (dạng `NNN-xxxx.apps.googleusercontent.com`). Người dùng dán vào Cài đặt.
    var googleClientID: String {
        didSet { defaults.set(GoogleAuth.cleanClientID(googleClientID), forKey: Keys.clientID) }
    }

    private(set) var appleLastUpdated: Date?
    private(set) var googleLastUpdated: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.source = HealthSource(rawValue: defaults.string(forKey: Keys.source) ?? "") ?? .apple
        // Client ID: ưu tiên giá trị đã lưu; lần đầu nạp sẵn từ Info.plist (GoogleHealthClientID) nếu có.
        let saved = defaults.string(forKey: Keys.clientID)
        let bundled = (Bundle.main.object(forInfoDictionaryKey: "GoogleHealthClientID") as? String)?
            .trimmingCharacters(in: .whitespaces)
        self.googleClientID = saved ?? (bundled?.isEmpty == false ? bundled! : "")
        self.appleLastUpdated = defaults.object(forKey: Keys.appleUpdated) as? Date
        self.googleLastUpdated = defaults.object(forKey: Keys.googleUpdated) as? Date
    }

    /// Ghi lại "cập nhật lần cuối" cho nguồn vừa tải xong.
    func recordUpdate(for source: HealthSource, at date: Date = Date()) {
        if source.usesGoogle {
            googleLastUpdated = date
            defaults.set(date, forKey: Keys.googleUpdated)
        }
        if source != .google {
            appleLastUpdated = date
            defaults.set(date, forKey: Keys.appleUpdated)
        }
    }

    /// "cập nhật lần cuối" theo nguồn, để hiện trong Cài đặt.
    func lastUpdated(for source: HealthSource) -> Date? {
        source == .google ? googleLastUpdated : appleLastUpdated
    }
}

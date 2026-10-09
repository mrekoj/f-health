import Foundation
import Observation

/// Hướng mục tiêu cân nặng — quyết định cách tô màu ô Cân nặng (tăng: dưới mục tiêu là đỏ; giảm: ngược lại).
enum WeightGoalDirection: String, Codable, CaseIterable, Identifiable {
    case gain, lose, keep
    var id: String { rawValue }
    var label: String {
        switch self {
        case .gain: return "Tăng cân"
        case .lose: return "Giảm cân"
        case .keep: return "Giữ cân"
        }
    }
}

enum ProfileSex: String, Codable, CaseIterable, Identifiable {
    case male, female, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .male: return "Nam"
        case .female: return "Nữ"
        case .other: return "Khác"
        }
    }
}

/// **Hồ sơ cá nhân** — người dùng sửa được trong Cài đặt → Hồ sơ của tôi (T-025).
/// Dùng cho 2 việc: (1) ngưỡng/mục tiêu cá nhân (`Thresholds` đọc từ đây); (2) phần "Hồ sơ" trong gói
/// báo cáo gửi AI (bệnh nền, BS dặn, kiêng, thuốc…). Mặc định trống; mỗi người tự điền trong app
/// hoặc đặt file riêng `Resources/Private/OwnerProfile.json` (gitignore).
struct HealthProfile: Codable, Equatable {
    /// Tên gọi ngắn (vd "Minh") — AI dùng để xưng hô.
    var displayName: String
    /// Cách gọi: "anh" / "chị" / "em" / "bạn" — để lời khuyên đúng vai.
    var addressAs: String
    var birthYear: Int
    var sex: ProfileSex
    var heightCm: Double?
    /// Mục tiêu cân (kg) + hướng (tăng/giảm/giữ).
    var weightGoalKg: Double
    var weightDirection: WeightGoalDirection
    /// Mục tiêu ngủ (giờ/đêm) và bước/ngày.
    var sleepGoalHours: Double
    var stepsGoal: Int
    /// Bệnh nền đang theo dõi (mỗi dòng một bệnh).
    var conditions: String
    /// Lời bác sĩ dặn (bắt buộc theo).
    var doctorNotes: String
    /// Ăn uống: kiêng gì, ăn thế nào.
    var dietNotes: String
    /// Thuốc / thực phẩm bổ sung đang dùng.
    var medications: String
    /// Lối sống: công việc, rượu bia, tập luyện, ngủ…
    var lifestyleNotes: String
    var updatedAt: Date

    var age: Int {
        let y = Calendar.current.component(.year, from: Date())
        return max(0, y - birthYear)
    }

    /// BMI từ chiều cao + cân (nil nếu thiếu).
    func bmi(kg: Double) -> Double? {
        guard let h = heightCm, h > 0 else { return nil }
        let m = h / 100
        return kg / (m * m)
    }

    /// Hồ sơ riêng của người cài app, nạp từ `Resources/Private/OwnerProfile.json` (file này nằm trong
    /// .gitignore — KHÔNG commit). Không có file → nil, app dùng hồ sơ trống và mời người dùng tự điền.
    /// Mẫu file: `Resources/Private/OwnerProfile.example.json`.
    static let owner: HealthProfile? = {
        guard let url = Bundle.main.url(forResource: "OwnerProfile", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(HealthProfile.self, from: data)
    }()

    /// Hồ sơ khi chưa có gì: hồ sơ riêng (nếu có file) hoặc hồ sơ trống.
    static var initial: HealthProfile { owner ?? .blank }

    /// true khi người dùng chưa điền tên — màn Hôm nay mời điền hồ sơ.
    var isEmpty: Bool { displayName.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Cách gọi người dùng trong câu ("anh"/"chị"/"bạn"…); hồ sơ trống → "bạn".
    var you: String {
        let a = addressAs.trimmingCharacters(in: .whitespaces)
        return isEmpty || a.isEmpty ? "bạn" : a
    }

    /// Hồ sơ trống cho người dùng mới (chỉ giữ mục tiêu chung).
    static let blank = HealthProfile(
        displayName: "", addressAs: "bạn", birthYear: 1990, sex: .other, heightCm: nil,
        weightGoalKg: 60, weightDirection: .keep, sleepGoalHours: 7, stepsGoal: 6_000,
        conditions: "", doctorNotes: "", dietNotes: "", medications: "", lifestyleNotes: "",
        updatedAt: Date())
}

/// Kho lưu hồ sơ (UserDefaults, JSON). Đọc được từ mọi luồng — `Thresholds` gọi hàm này rất nhiều
/// nên có cache bằng khoá; ghi qua `save` để cache và đĩa luôn khớp.
enum HealthProfileStore {
    private static let key = "bbh.profile.v1"
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: HealthProfile?

    static var current: HealthProfile {
        lock.lock(); defer { lock.unlock() }
        if let c = cache { return c }
        let loaded = load()
        cache = loaded
        return loaded
    }

    static func save(_ profile: HealthProfile) {
        lock.lock(); defer { lock.unlock() }
        cache = profile
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        cache = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private static func load() -> HealthProfile {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(HealthProfile.self, from: data) else { return .initial }
        return p
    }
}

/// Bản @Observable cho màn Hồ sơ: sửa `profile` → tự lưu.
@Observable
@MainActor
final class ProfileSettings {
    static let shared = ProfileSettings()

    var profile: HealthProfile {
        didSet {
            // @Observable biến `profile` thành thuộc tính tính toán → gán lại trong didSet sẽ gọi lại
            // didSet (khác struct thường). Không chặn thì `updatedAt = Date()` đệ quy tới tràn stack (crash khi lưu hồ sơ).
            guard !isStamping, profile != oldValue else { return }
            isStamping = true
            profile.updatedAt = Date()
            isStamping = false
            HealthProfileStore.save(profile)
        }
    }
    @ObservationIgnored private var isStamping = false

    init() { profile = HealthProfileStore.current }

    /// Về hồ sơ mặc định (file riêng OwnerProfile.json nếu có, không thì hồ sơ trống).
    func restoreOwner() { profile = .initial }
    /// Xoá trắng cho người dùng mới.
    func clear() { profile = .blank }
}

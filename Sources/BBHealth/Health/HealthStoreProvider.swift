import Foundation

/// Tóm tắt giấc ngủ của một đêm (đêm trước ngày `date`).
struct SleepSummary: Equatable {
    /// Tổng thời gian ngủ thật (giờ), gồm ngủ nông/sâu/REM/không phân loại — không tính lúc thức.
    var totalHours: Double
    /// Số lần thức giấc giữa đêm.
    var awakeCount: Int
    /// Giờ bắt đầu ngủ.
    var bedTime: Date?
    /// Giờ dậy.
    var wakeTime: Date?
}

/// Nguồn dữ liệu sức khoẻ. Có nhiều bản:
/// - `HKHealthStoreProvider` (đọc HealthKit thật, tức Apple Health) và `MockHealthStoreProvider` (số giả).
/// - `GoogleHealthProvider` (gọi thẳng Google Health API v4) và `MockGoogleHealthProvider` (số giả).
/// - `CompositeProvider` (gộp 2 nguồn theo cấu hình: ưu tiên Google, thiếu thì lấy Apple).
///
/// `heartRateVariability` (HRV) và `skinTemperature` (nhiệt độ da) thường **chỉ có ở nguồn Google**
/// (Apple Health chưa nhận từ Fitbit) → mặc định trả `nil` để các bản khác khỏi bắt buộc cài đặt.
protocol HealthStoreProvider: Sendable {
    /// Có cần hỏi quyền người dùng không (lần đầu mở app / chưa đăng nhập Google).
    func authorizationRequestNeeded() async -> Bool
    /// Xin quyền đọc ngủ/nhịp tim nghỉ/bước/cân và ghi cân (hoặc đăng nhập Google).
    func requestAuthorization() async throws
    /// Giấc ngủ của đêm trước ngày `date` (cửa sổ 18h hôm trước → 12h trưa `date`).
    func sleepSummary(for date: Date) async throws -> SleepSummary?
    /// Các **giấc ngủ ngày / ngủ trưa** trong NGÀY `date` (đã loại phiên ngủ đêm chính).
    /// Có default impl trả `[]` cho nguồn chưa đọc được giấc ngày (vd Google v4beta best-effort).
    func daytimeSleeps(for date: Date) async throws -> [NapSummary]
    /// Giấc trưa **ước tính từ nhịp tim** (khi Fitbit không ghi phiên ngủ). Có default impl dùng
    /// `NapDetector` trên `intradayHeartRate` + `restingHeartRate` → Apple & Google đều dùng được.
    func estimatedDaytimeNaps(for date: Date) async throws -> [NapSummary]
    /// Nhịp tim nghỉ (lần/phút) của ngày `date`.
    func restingHeartRate(for date: Date) async throws -> Double?
    /// Tổng số bước trong ngày `date`.
    func steps(for date: Date) async throws -> Int?
    /// Cân nặng mới nhất (kg) và ngày đo.
    func latestBodyMass() async throws -> (kg: Double, date: Date)?
    /// Ghi cân nặng vào nguồn (thực tế chỉ Apple Health ghi được).
    func saveBodyMass(kg: Double, date: Date) async throws
    /// Chi tiết giấc ngủ (các giai đoạn) của đêm trước ngày `date` — cho màn Giấc ngủ chi tiết.
    func sleepDetail(for date: Date) async throws -> SleepDetail?
    /// Biến thiên nhịp tim (HRV, mili-giây) của đêm trước ngày `date` — thường chỉ Google có.
    func heartRateVariability(for date: Date) async throws -> Double?
    /// Nhiệt độ da: chênh lệch so với nền (°C) của đêm trước ngày `date` — thường chỉ Google có.
    func skinTemperature(for date: Date) async throws -> Double?
    /// Nhịp tim theo giờ/khoảng trong ngày `date` (cho màn Nhịp tim chi tiết).
    /// Trả `nil` khi nguồn không có dữ liệu intraday → màn hình tự ẩn khối này.
    func intradayHeartRate(for date: Date) async throws -> [(time: Date, bpm: Double)]?

    // MARK: - Sinh hiệu & vận động (T-020) — default impl trả nil/[] để không phá nguồn nào
    /// Nhịp thở trung bình (lần/phút) của đêm trước ngày `date`.
    func respiratoryRate(for date: Date) async throws -> Double?
    /// Oxy máu (SpO2, %) trung bình của đêm trước ngày `date`.
    func oxygenSaturation(for date: Date) async throws -> Double?
    /// Quãng đường đi bộ/chạy trong ngày `date` (km).
    func distanceKm(for date: Date) async throws -> Double?
    /// Năng lượng đốt khi vận động (kcal, không tính calo nền) trong ngày `date`.
    func activeEnergyKcal(for date: Date) async throws -> Double?
    /// Số bước theo từng giờ (0–23) của ngày `date` — để đếm "giờ có vận động" (≥ 250 bước).
    func hourlySteps(for date: Date) async throws -> [(hour: Int, steps: Int)]

    // MARK: - Dải ngày (cho màn Xu hướng)
    /// Giấc ngủ mỗi đêm trong khoảng `[from, to]` (theo ngày).
    func sleepSummaries(from: Date, to: Date) async throws -> [(date: Date, summary: SleepSummary)]
    /// Nhịp tim nghỉ mỗi ngày trong khoảng.
    func restingHeartRates(from: Date, to: Date) async throws -> [(date: Date, bpm: Double)]
    /// Số bước mỗi ngày trong khoảng.
    func stepsSeries(from: Date, to: Date) async throws -> [(date: Date, steps: Int)]
    /// Các lần cân trong khoảng.
    func bodyMasses(from: Date, to: Date) async throws -> [(date: Date, kg: Double)]
    /// Biến thiên nhịp tim (HRV, ms) mỗi ngày trong khoảng — thường chỉ Google có.
    func heartRateVariabilities(from: Date, to: Date) async throws -> [(date: Date, ms: Double)]
    /// Nhiệt độ da (chênh so với nền, °C) mỗi ngày trong khoảng — thường chỉ Google có.
    func skinTemperatures(from: Date, to: Date) async throws -> [(date: Date, delta: Double)]
    /// Dải nhịp tim (thấp nhất–cao nhất) + nhịp tim nghỉ mỗi ngày trong khoảng —
    /// cho chế độ Tuần/Tháng của màn Nhịp tim chi tiết (kiểu Google Health).
    func heartRateDailyRanges(from: Date, to: Date) async throws -> [(date: Date, min: Double, max: Double, resting: Double?)]
    /// Quãng đường (km) mỗi ngày trong khoảng.
    func distanceSeries(from: Date, to: Date) async throws -> [(date: Date, km: Double)]
    /// Số giờ có vận động (giờ có ≥ 250 bước) mỗi ngày trong khoảng.
    func activeHoursSeries(from: Date, to: Date) async throws -> [(date: Date, hours: Int)]
}

/// Ngưỡng "giờ có vận động" giống Google Health (Hourly activity): giờ có ≥ 250 bước.
enum ActiveHours {
    static let stepsPerHour = 250
    static let goal = 9
    static func count(_ hourly: [(hour: Int, steps: Int)]) -> Int {
        hourly.filter { $0.steps >= stepsPerHour }.count
    }
}

extension HealthStoreProvider {
    /// Mặc định: nguồn không đọc được giấc ngày → không có số (đừng bịa).
    func daytimeSleeps(for date: Date) async throws -> [NapSummary] { [] }
    /// Mặc định: suy giấc trưa từ nhịp tim trong ngày + nhịp nghỉ (dùng chung cho Apple & Google;
    /// nguồn nào không có intraday → `NapDetector` trả rỗng).
    func estimatedDaytimeNaps(for date: Date) async throws -> [NapSummary] {
        let points = ((try? await intradayHeartRate(for: date)) ?? nil) ?? []
        let resting = (try? await restingHeartRate(for: date)) ?? nil
        return NapDetector.fromHeartRate(points, resting: resting, day: date)
    }
    func napDiagnostics(for date: Date) async throws -> NapDetector.Diagnostics? {
        let points = ((try? await intradayHeartRate(for: date)) ?? nil) ?? []
        let resting = (try? await restingHeartRate(for: date)) ?? nil
        return NapDetector.diagnose(points, resting: resting, day: date)
    }
    func sleepDetail(for date: Date) async throws -> SleepDetail? { nil }
    func heartRateVariability(for date: Date) async throws -> Double? { nil }
    func skinTemperature(for date: Date) async throws -> Double? { nil }
    func intradayHeartRate(for date: Date) async throws -> [(time: Date, bpm: Double)]? { nil }
    func respiratoryRate(for date: Date) async throws -> Double? { nil }
    func oxygenSaturation(for date: Date) async throws -> Double? { nil }
    func distanceKm(for date: Date) async throws -> Double? { nil }
    func activeEnergyKcal(for date: Date) async throws -> Double? { nil }
    func hourlySteps(for date: Date) async throws -> [(hour: Int, steps: Int)] { [] }

    func distanceSeries(from: Date, to: Date) async throws -> [(date: Date, km: Double)] {
        var out: [(date: Date, km: Double)] = []
        for day in Self.days(from: from, to: to) {
            if let v = (try? await distanceKm(for: day)) ?? nil { out.append((day, v)) }
        }
        return out
    }
    /// Ngày không có số bước theo giờ (nguồn không hỗ trợ) thì bỏ qua — không coi là 0 giờ.
    func activeHoursSeries(from: Date, to: Date) async throws -> [(date: Date, hours: Int)] {
        var out: [(date: Date, hours: Int)] = []
        for day in Self.days(from: from, to: to) {
            let hourly = (try? await hourlySteps(for: day)) ?? []
            if !hourly.isEmpty { out.append((day, ActiveHours.count(hourly))) }
        }
        return out
    }

    /// Mặc định: lặp từng ngày gọi hàm 1-ngày (đúng cho Apple/Google; mock ghi đè cho nhanh).
    func sleepSummaries(from: Date, to: Date) async throws -> [(date: Date, summary: SleepSummary)] {
        var out: [(date: Date, summary: SleepSummary)] = []
        for day in Self.days(from: from, to: to) {
            if let s = try? await sleepSummary(for: day) { out.append((day, s)) }
        }
        return out
    }
    func restingHeartRates(from: Date, to: Date) async throws -> [(date: Date, bpm: Double)] {
        var out: [(date: Date, bpm: Double)] = []
        for day in Self.days(from: from, to: to) {
            if let v = try? await restingHeartRate(for: day) { out.append((day, v)) }
        }
        return out
    }
    func stepsSeries(from: Date, to: Date) async throws -> [(date: Date, steps: Int)] {
        var out: [(date: Date, steps: Int)] = []
        for day in Self.days(from: from, to: to) {
            if let v = try? await steps(for: day) { out.append((day, v)) }
        }
        return out
    }
    func bodyMasses(from: Date, to: Date) async throws -> [(date: Date, kg: Double)] {
        // Mặc định chỉ có lần cân mới nhất (Apple/Google trả 1 điểm); mock sinh cả dải.
        if let m = try? await latestBodyMass() { return [(m.date, m.kg)] }
        return []
    }
    func heartRateVariabilities(from: Date, to: Date) async throws -> [(date: Date, ms: Double)] {
        var out: [(date: Date, ms: Double)] = []
        for day in Self.days(from: from, to: to) {
            if let v = try? await heartRateVariability(for: day) { out.append((day, v)) }
        }
        return out
    }
    func skinTemperatures(from: Date, to: Date) async throws -> [(date: Date, delta: Double)] {
        var out: [(date: Date, delta: Double)] = []
        for day in Self.days(from: from, to: to) {
            if let v = try? await skinTemperature(for: day) { out.append((day, v)) }
        }
        return out
    }

    /// Mặc định: mỗi ngày lấy intraday → tính thấp/cao nhất; `restingHeartRate` cho nhịp nghỉ.
    /// Không có intraday thì dùng nhịp nghỉ cho cả min=max (để Tuần/Tháng vẫn có chấm).
    /// Apple ghi đè bằng `HKStatisticsCollectionQuery` cho chính xác hơn.
    func heartRateDailyRanges(from: Date, to: Date) async throws -> [(date: Date, min: Double, max: Double, resting: Double?)] {
        var out: [(date: Date, min: Double, max: Double, resting: Double?)] = []
        for day in Self.days(from: from, to: to) {
            let resting = (try? await restingHeartRate(for: day)) ?? nil
            if let intraday = (try? await intradayHeartRate(for: day)) ?? nil, !intraday.isEmpty {
                let bpms = intraday.map(\.bpm)
                if let lo = bpms.min(), let hi = bpms.max() {
                    out.append((day, lo, hi, resting))
                    continue
                }
            }
            if let r = resting { out.append((day, r, r, r)) }
        }
        return out
    }

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
}

enum HealthStoreFactory {
    /// Nguồn Apple (mặc định) — dùng cho ghi cân nặng và tương thích ngược.
    static func make() -> any HealthStoreProvider { appleProvider() }

    /// Chọn nguồn dữ liệu theo cấu hình người dùng.
    static func make(for source: HealthSource) -> any HealthStoreProvider {
        switch source {
        case .apple:
            return appleProvider()
        case .google:
            return googleProvider()
        case .both:
            // Ưu tiên Google, thiếu thì lấy Apple.
            return CompositeProvider(primary: googleProvider(), fallback: appleProvider())
        }
    }

    /// Nguồn Apple Health: simulator/`BBH_MOCK=1` → số giả; iPhone thật → HealthKit.
    static func appleProvider() -> any HealthStoreProvider {
        useMock ? MockHealthStoreProvider() : HKHealthStoreProvider()
    }

    /// Nguồn Google Health: simulator/`BBH_MOCK=1` → số giả; iPhone thật → gọi Google Health API.
    static func googleProvider() -> any HealthStoreProvider {
        useMock ? MockGoogleHealthProvider() : GoogleHealthProvider()
    }

    static var useMock: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return ProcessInfo.processInfo.environment["BBH_MOCK"] == "1"
        #endif
    }
}

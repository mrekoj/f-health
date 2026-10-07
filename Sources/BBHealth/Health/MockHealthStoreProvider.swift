import Foundation

/// Số giả hợp lý để chạy trên simulator/preview (HealthKit trên sim không có dữ liệu Fitbit).
/// Đây là nguồn **Apple Health** giả → không có HRV / nhiệt độ da (giống thực tế Fitbit chưa ghi sang).
final class MockHealthStoreProvider: HealthStoreProvider, @unchecked Sendable {
    private static let authorizedKey = "bbh.mock.authorized"
    private var authorized: Bool
    private var overriddenBodyMass: (kg: Double, date: Date)?

    /// `BBH_MOCK=1` → coi như đã cấp quyền (xem ngay số giả). Chạy sim thường → hiện màn xin quyền
    /// một lần, sau đó nhớ lại (UserDefaults) để giống hành vi thật.
    init(authorized: Bool? = nil) {
        if let authorized {
            self.authorized = authorized
        } else {
            self.authorized = ProcessInfo.processInfo.environment["BBH_MOCK"] == "1"
                || UserDefaults.standard.bool(forKey: Self.authorizedKey)
        }
    }

    func authorizationRequestNeeded() async -> Bool { !authorized }

    func requestAuthorization() async throws {
        try? await Task.sleep(for: .milliseconds(400))
        authorized = true
        UserDefaults.standard.set(true, forKey: Self.authorizedKey)
    }

    // Suy từ chi tiết để Hôm nay và màn chi tiết luôn khớp (cùng cách lấp khoảng thức, cùng awakeCount).
    func sleepSummary(for date: Date) async throws -> SleepSummary? {
        try? await Task.sleep(for: .milliseconds(200))
        return try await sleepDetail(for: date)?.summary
    }

    func sleepDetail(for date: Date) async throws -> SleepDetail? { MockData.sleepDetail(date) }

    func daytimeSleeps(for date: Date) async throws -> [NapSummary] { MockData.daytimeSleeps(date) }

    func restingHeartRate(for date: Date) async throws -> Double? { MockData.restingHeartRate(date) }

    func steps(for date: Date) async throws -> Int? { MockData.steps(date) }

    func latestBodyMass() async throws -> (kg: Double, date: Date)? {
        if let overriddenBodyMass { return overriddenBodyMass }
        let cal = Calendar.current
        let sevenAM = cal.date(bySettingHour: 7, minute: 5, second: 0, of: Date()) ?? Date()
        return (MockData.weight(Date()), sevenAM)
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        overriddenBodyMass = (kg, date)
    }

    // Nguồn Apple: không có HRV / nhiệt độ da → dùng mặc định nil của protocol.
    // Nhịp tim theo giờ thì Apple Health có (HealthKit ghi mẫu nhịp tim) → mock sinh đường cong
    // để màn Nhịp tim chi tiết xem được trên simulator với nguồn Apple mặc định.
    func intradayHeartRate(for date: Date) async throws -> [(time: Date, bpm: Double)]? {
        let points = MockData.intradayHeartRate(date)
        return points.isEmpty ? nil : points
    }

    // Sinh hiệu & vận động: Apple Health có nhận nhịp thở, SpO2, quãng đường, calo, bước (Google Health ghi sang).
    func respiratoryRate(for date: Date) async throws -> Double? { MockData.respiratoryRate(date) }
    func oxygenSaturation(for date: Date) async throws -> Double? { MockData.oxygenSaturation(date) }
    func distanceKm(for date: Date) async throws -> Double? { MockData.distanceKm(date) }
    func activeEnergyKcal(for date: Date) async throws -> Double? { MockData.activeEnergyKcal(date) }
    func hourlySteps(for date: Date) async throws -> [(hour: Int, steps: Int)] { MockData.hourlySteps(date) }

    // MARK: - Dải ngày (sinh cả chuỗi cho màn Xu hướng)

    func distanceSeries(from: Date, to: Date) async throws -> [(date: Date, km: Double)] {
        Self.days(from: from, to: to).map { ($0, MockData.distanceKm($0)) }
    }
    func activeHoursSeries(from: Date, to: Date) async throws -> [(date: Date, hours: Int)] {
        Self.days(from: from, to: to).map { ($0, ActiveHours.count(MockData.hourlySteps($0))) }
    }

    func sleepSummaries(from: Date, to: Date) async throws -> [(date: Date, summary: SleepSummary)] {
        Self.days(from: from, to: to).map { ($0, MockData.sleepSummary($0)) }
    }
    func restingHeartRates(from: Date, to: Date) async throws -> [(date: Date, bpm: Double)] {
        Self.days(from: from, to: to).map { ($0, MockData.restingHeartRate($0)) }
    }
    func stepsSeries(from: Date, to: Date) async throws -> [(date: Date, steps: Int)] {
        Self.days(from: from, to: to).map { ($0, MockData.steps($0)) }
    }
    func bodyMasses(from: Date, to: Date) async throws -> [(date: Date, kg: Double)] {
        // Cân 3 lần/tuần cho giống thực tế.
        Self.days(from: from, to: to)
            .filter { [2, 4, 6].contains(Calendar.current.component(.weekday, from: $0)) }
            .map { ($0, MockData.weight($0)) }
    }
    func heartRateDailyRanges(from: Date, to: Date) async throws -> [(date: Date, min: Double, max: Double, resting: Double?)] {
        Self.days(from: from, to: to).map {
            let r = MockData.heartRateDailyRange($0)
            return ($0, r.min, r.max, r.resting)
        }
    }
}

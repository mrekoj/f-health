import Foundation

/// Nguồn **Google Health giả** cho simulator/preview: giống Apple giả nhưng có thêm HRV và
/// nhiệt độ da (đúng như Google Health API mới có). Trạng thái kết nối theo `GoogleAuth` (cờ giả).
final class MockGoogleHealthProvider: HealthStoreProvider, @unchecked Sendable {
    func authorizationRequestNeeded() async -> Bool {
        await !GoogleAuth.shared.isConnected
    }

    func requestAuthorization() async throws {
        let clientID = await AppSettings.shared.googleClientID
        // Trên sim, GoogleAuth tự bỏ qua OAuth thật và bật cờ kết nối giả.
        try await GoogleAuth.shared.signIn(clientID: clientID.isEmpty ? "mock.apps.googleusercontent.com" : clientID)
    }

    private func connected() async -> Bool { await GoogleAuth.shared.isConnected }

    // Suy từ chi tiết để Hôm nay và màn chi tiết luôn khớp (cùng cách lấp khoảng thức, cùng awakeCount).
    func sleepSummary(for date: Date) async throws -> SleepSummary? {
        guard await connected() else { return nil }
        try? await Task.sleep(for: .milliseconds(200))
        return try await sleepDetail(for: date)?.summary
    }

    func sleepDetail(for date: Date) async throws -> SleepDetail? {
        guard await connected() else { return nil }
        return MockData.sleepDetail(date)
    }

    func daytimeSleeps(for date: Date) async throws -> [NapSummary] {
        guard await connected() else { return [] }
        return MockData.daytimeSleeps(date)
    }

    func restingHeartRate(for date: Date) async throws -> Double? {
        guard await connected() else { return nil }
        return MockData.restingHeartRate(date)
    }

    func steps(for date: Date) async throws -> Int? {
        guard await connected() else { return nil }
        return MockData.steps(date)
    }

    func latestBodyMass() async throws -> (kg: Double, date: Date)? {
        guard await connected() else { return nil }
        let cal = Calendar.current
        let sevenAM = cal.date(bySettingHour: 7, minute: 2, second: 0, of: Date()) ?? Date()
        return (MockData.weight(Date()), sevenAM)
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        // Google là nguồn chỉ-đọc; ghi cân đi qua Apple Health.
    }

    func heartRateVariability(for date: Date) async throws -> Double? {
        guard await connected() else { return nil }
        return MockData.hrv(date)
    }

    func skinTemperature(for date: Date) async throws -> Double? {
        guard await connected() else { return nil }
        return MockData.skinTempDelta(date)
    }

    func intradayHeartRate(for date: Date) async throws -> [(time: Date, bpm: Double)]? {
        guard await connected() else { return nil }
        let points = MockData.intradayHeartRate(date)
        return points.isEmpty ? nil : points
    }

    // Sinh hiệu & vận động (T-020).
    func respiratoryRate(for date: Date) async throws -> Double? {
        guard await connected() else { return nil }
        return MockData.respiratoryRate(date)
    }
    func oxygenSaturation(for date: Date) async throws -> Double? {
        guard await connected() else { return nil }
        return MockData.oxygenSaturation(date)
    }
    func distanceKm(for date: Date) async throws -> Double? {
        guard await connected() else { return nil }
        return MockData.distanceKm(date)
    }
    func activeEnergyKcal(for date: Date) async throws -> Double? {
        guard await connected() else { return nil }
        return MockData.activeEnergyKcal(date)
    }
    func hourlySteps(for date: Date) async throws -> [(hour: Int, steps: Int)] {
        guard await connected() else { return [] }
        return MockData.hourlySteps(date)
    }

    // MARK: - Dải ngày

    func distanceSeries(from: Date, to: Date) async throws -> [(date: Date, km: Double)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map { ($0, MockData.distanceKm($0)) }
    }
    func activeHoursSeries(from: Date, to: Date) async throws -> [(date: Date, hours: Int)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map { ($0, ActiveHours.count(MockData.hourlySteps($0))) }
    }

    func sleepSummaries(from: Date, to: Date) async throws -> [(date: Date, summary: SleepSummary)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map { ($0, MockData.sleepSummary($0)) }
    }
    func restingHeartRates(from: Date, to: Date) async throws -> [(date: Date, bpm: Double)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map { ($0, MockData.restingHeartRate($0)) }
    }
    func stepsSeries(from: Date, to: Date) async throws -> [(date: Date, steps: Int)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map { ($0, MockData.steps($0)) }
    }
    func bodyMasses(from: Date, to: Date) async throws -> [(date: Date, kg: Double)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to)
            .filter { [2, 4, 6].contains(Calendar.current.component(.weekday, from: $0)) }
            .map { ($0, MockData.weight($0)) }
    }
    func heartRateVariabilities(from: Date, to: Date) async throws -> [(date: Date, ms: Double)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map { ($0, MockData.hrv($0)) }
    }
    func skinTemperatures(from: Date, to: Date) async throws -> [(date: Date, delta: Double)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map { ($0, MockData.skinTempDelta($0)) }
    }
    func heartRateDailyRanges(from: Date, to: Date) async throws -> [(date: Date, min: Double, max: Double, resting: Double?)] {
        guard await connected() else { return [] }
        return Self.days(from: from, to: to).map {
            let r = MockData.heartRateDailyRange($0)
            return ($0, r.min, r.max, r.resting)
        }
    }
}

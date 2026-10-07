import Foundation

/// Gộp hai nguồn: **ưu tiên `primary` (Google), chỉ số nào thiếu thì lấy `fallback` (Apple)**.
///
/// Màn Hôm nay không chặn vì chuyện đăng nhập Google: quyền được tính theo Apple (fallback),
/// còn Google là tuỳ chọn bật trong Cài đặt.
final class CompositeProvider: HealthStoreProvider, @unchecked Sendable {
    private let primary: any HealthStoreProvider
    private let fallback: any HealthStoreProvider

    init(primary: any HealthStoreProvider, fallback: any HealthStoreProvider) {
        self.primary = primary
        self.fallback = fallback
    }

    func authorizationRequestNeeded() async -> Bool {
        await fallback.authorizationRequestNeeded()
    }

    func requestAuthorization() async throws {
        try await fallback.requestAuthorization()
    }

    // Suy từ CHÍNH `sleepDetail` gộp (Google trước, thiếu thì Apple) để Hôm nay khớp hệt màn chi tiết.
    func sleepSummary(for date: Date) async throws -> SleepSummary? {
        try await sleepDetail(for: date)?.summary
    }

    func sleepDetail(for date: Date) async throws -> SleepDetail? {
        if let v = try? await primary.sleepDetail(for: date), !v.segments.isEmpty { return v }
        return try await fallback.sleepDetail(for: date)
    }

    func daytimeSleeps(for date: Date) async throws -> [NapSummary] {
        if let v = try? await primary.daytimeSleeps(for: date), !v.isEmpty { return v }
        return (try? await fallback.daytimeSleeps(for: date)) ?? []
    }

    func restingHeartRate(for date: Date) async throws -> Double? {
        if let v = try? await primary.restingHeartRate(for: date) { return v }
        return try await fallback.restingHeartRate(for: date)
    }

    func steps(for date: Date) async throws -> Int? {
        if let v = try? await primary.steps(for: date) { return v }
        return try await fallback.steps(for: date)
    }

    func latestBodyMass() async throws -> (kg: Double, date: Date)? {
        if let v = try? await primary.latestBodyMass() { return v }
        return try await fallback.latestBodyMass()
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        // Ghi cân luôn vào Apple Health (nguồn ghi được).
        try await fallback.saveBodyMass(kg: kg, date: date)
    }

    func heartRateVariability(for date: Date) async throws -> Double? {
        if let v = try? await primary.heartRateVariability(for: date) { return v }
        return try? await fallback.heartRateVariability(for: date)
    }

    func skinTemperature(for date: Date) async throws -> Double? {
        if let v = try? await primary.skinTemperature(for: date) { return v }
        return try? await fallback.skinTemperature(for: date)
    }

    func intradayHeartRate(for date: Date) async throws -> [(time: Date, bpm: Double)]? {
        if let v = try? await primary.intradayHeartRate(for: date), !v.isEmpty { return v }
        return try? await fallback.intradayHeartRate(for: date)
    }

    // MARK: - Sinh hiệu & vận động (T-020): Google trước, thiếu thì Apple

    func respiratoryRate(for date: Date) async throws -> Double? {
        if let v = (try? await primary.respiratoryRate(for: date)) ?? nil { return v }
        return (try? await fallback.respiratoryRate(for: date)) ?? nil
    }
    func oxygenSaturation(for date: Date) async throws -> Double? {
        if let v = (try? await primary.oxygenSaturation(for: date)) ?? nil { return v }
        return (try? await fallback.oxygenSaturation(for: date)) ?? nil
    }
    func distanceKm(for date: Date) async throws -> Double? {
        if let v = (try? await primary.distanceKm(for: date)) ?? nil { return v }
        return (try? await fallback.distanceKm(for: date)) ?? nil
    }
    func activeEnergyKcal(for date: Date) async throws -> Double? {
        if let v = (try? await primary.activeEnergyKcal(for: date)) ?? nil { return v }
        return (try? await fallback.activeEnergyKcal(for: date)) ?? nil
    }
    func hourlySteps(for date: Date) async throws -> [(hour: Int, steps: Int)] {
        if let v = try? await primary.hourlySteps(for: date), !v.isEmpty { return v }
        return (try? await fallback.hourlySteps(for: date)) ?? []
    }

    // MARK: - Dải ngày: ưu tiên chuỗi Google, rỗng thì lấy Apple

    func distanceSeries(from: Date, to: Date) async throws -> [(date: Date, km: Double)] {
        let p = (try? await primary.distanceSeries(from: from, to: to)) ?? []
        return p.isEmpty ? ((try? await fallback.distanceSeries(from: from, to: to)) ?? []) : p
    }
    func activeHoursSeries(from: Date, to: Date) async throws -> [(date: Date, hours: Int)] {
        let p = (try? await primary.activeHoursSeries(from: from, to: to)) ?? []
        return p.isEmpty ? ((try? await fallback.activeHoursSeries(from: from, to: to)) ?? []) : p
    }

    func sleepSummaries(from: Date, to: Date) async throws -> [(date: Date, summary: SleepSummary)] {
        let p = (try? await primary.sleepSummaries(from: from, to: to)) ?? []
        return p.isEmpty ? try await fallback.sleepSummaries(from: from, to: to) : p
    }
    func restingHeartRates(from: Date, to: Date) async throws -> [(date: Date, bpm: Double)] {
        let p = (try? await primary.restingHeartRates(from: from, to: to)) ?? []
        return p.isEmpty ? try await fallback.restingHeartRates(from: from, to: to) : p
    }
    func stepsSeries(from: Date, to: Date) async throws -> [(date: Date, steps: Int)] {
        let p = (try? await primary.stepsSeries(from: from, to: to)) ?? []
        return p.isEmpty ? try await fallback.stepsSeries(from: from, to: to) : p
    }
    func bodyMasses(from: Date, to: Date) async throws -> [(date: Date, kg: Double)] {
        let p = (try? await primary.bodyMasses(from: from, to: to)) ?? []
        return p.isEmpty ? try await fallback.bodyMasses(from: from, to: to) : p
    }
    func heartRateVariabilities(from: Date, to: Date) async throws -> [(date: Date, ms: Double)] {
        let p = (try? await primary.heartRateVariabilities(from: from, to: to)) ?? []
        return p.isEmpty ? ((try? await fallback.heartRateVariabilities(from: from, to: to)) ?? []) : p
    }
    func skinTemperatures(from: Date, to: Date) async throws -> [(date: Date, delta: Double)] {
        let p = (try? await primary.skinTemperatures(from: from, to: to)) ?? []
        return p.isEmpty ? ((try? await fallback.skinTemperatures(from: from, to: to)) ?? []) : p
    }
    func heartRateDailyRanges(from: Date, to: Date) async throws -> [(date: Date, min: Double, max: Double, resting: Double?)] {
        let p = (try? await primary.heartRateDailyRanges(from: from, to: to)) ?? []
        return p.isEmpty ? try await fallback.heartRateDailyRanges(from: from, to: to) : p
    }
}

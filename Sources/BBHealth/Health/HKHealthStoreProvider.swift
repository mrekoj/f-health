import Foundation
import HealthKit

/// Đọc dữ liệu thật từ HealthKit (Fitbit → Google Health → Apple Health).
final class HKHealthStoreProvider: HealthStoreProvider, @unchecked Sendable {
    private let store = HKHealthStore()

    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let restingHRType = HKQuantityType(.restingHeartRate)
    private let heartRateType = HKQuantityType(.heartRate)
    private let stepType = HKQuantityType(.stepCount)
    private let bodyMassType = HKQuantityType(.bodyMass)
    // T-020: sinh hiệu & vận động (chỉ ĐỌC).
    private let respiratoryType = HKQuantityType(.respiratoryRate)
    private let oxygenType = HKQuantityType(.oxygenSaturation)
    private let distanceType = HKQuantityType(.distanceWalkingRunning)
    private let activeEnergyType = HKQuantityType(.activeEnergyBurned)

    private var readTypes: Set<HKObjectType> {
        [sleepType, restingHRType, heartRateType, stepType, bodyMassType,
         respiratoryType, oxygenType, distanceType, activeEnergyType]
    }
    private var shareTypes: Set<HKSampleType> { [bodyMassType] }

    enum ProviderError: LocalizedError {
        case unavailable
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Máy này không có ứng dụng Sức khoẻ."
            }
        }
    }

    func authorizationRequestNeeded() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            let status = try await store.statusForAuthorizationRequest(toShare: shareTypes, read: readTypes)
            return status == .shouldRequest
        } catch {
            return true
        }
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw ProviderError.unavailable }
        try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Ngủ

    /// Suy thẳng từ `sleepDetail` để màn Hôm nay và màn chi tiết **không bao giờ lệch nhau**
    /// (cùng cửa sổ, cùng cách lấp khoảng thức, cùng `awakeCount` ≥ 5 phút).
    func sleepSummary(for date: Date) async throws -> SleepSummary? {
        try await sleepDetail(for: date)?.summary
    }

    // MARK: - Giấc ngủ chi tiết (giai đoạn)

    func sleepDetail(for date: Date) async throws -> SleepDetail? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let windowStart = cal.date(byAdding: .hour, value: -6, to: dayStart),
              let windowEnd = cal.date(byAdding: .hour, value: 12, to: dayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        guard !samples.isEmpty else { return nil }

        func stage(_ value: Int) -> SleepStage? {
            switch value {
            case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .light
            default: return nil // inBed: chỉ là ranh giới
            }
        }

        var segments = samples.compactMap { s -> SleepSegment? in
            guard let st = stage(s.value) else { return nil }
            return SleepSegment(stage: st, start: s.startDate, end: s.endDate)
        }
        // Nguồn chỉ ghi inBed (không phân giai đoạn) → coi cả đêm là ngủ nông.
        if segments.filter({ $0.stage != .awake }).isEmpty {
            let inBed = samples.filter { $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue }
            guard let b = inBed.map(\.startDate).min(), let w = inBed.map(\.endDate).max(), w > b else { return nil }
            segments = [SleepSegment(stage: .light, start: b, end: w)]
        }
        // Lấp các khoảng trống giữa đoạn ngủ thành THỨC (nguồn hay để trống lúc thức giữa đêm).
        return SleepDetail(segments: SleepDetail.fillingAwakeGaps(segments))
    }

    // MARK: - Giấc ngủ ngày / ngủ trưa

    /// Đọc giấc ngủ ngày: query toàn ngày `date` (nới ±2h), gom các mẫu "asleep*" thành **phiên**
    /// (cách nhau > 45 phút = phiên mới), loại **phiên ngủ đêm chính** (phiên dài nhất giao khung
    /// 20h–10h), các phiên còn lại nằm ban ngày (~08h–20h) = giấc trưa/ngủ ngày.
    func daytimeSleeps(for date: Date) async throws -> [NapSummary] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let windowStart = cal.date(byAdding: .hour, value: -2, to: dayStart),
              let windowEnd = cal.date(byAdding: .hour, value: 26, to: dayStart) else { return [] }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)]
        )
        let samples = try await descriptor.result(for: store)
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let asleep = samples.filter { asleepValues.contains($0.value) }
                            .sorted { $0.startDate < $1.startDate }
        guard !asleep.isEmpty else { return [] }

        // Gom thành phiên: khoảng cách giữa 2 mẫu ngủ > 45 phút ⇒ phiên mới.
        struct Session { var start: Date; var end: Date; var stages: [SleepStage: Int] }
        var sessions: [Session] = []
        let gap: TimeInterval = 45 * 60
        for s in asleep {
            let st = Self.napStage(s.value)
            if var last = sessions.last, s.startDate.timeIntervalSince(last.end) <= gap {
                last.end = max(last.end, s.endDate)
                if let st { last.stages[st, default: 0] += Int(s.endDate.timeIntervalSince(s.startDate) / 60) }
                sessions[sessions.count - 1] = last
            } else {
                var stages: [SleepStage: Int] = [:]
                if let st { stages[st] = Int(s.endDate.timeIntervalSince(s.startDate) / 60) }
                sessions.append(Session(start: s.startDate, end: s.endDate, stages: stages))
            }
        }

        // Phiên ngủ đêm chính = phiên dài nhất có giao với khung 20h–10h.
        func overlapsNight(_ ses: Session) -> Bool {
            var t = ses.start
            while t < ses.end {
                let h = cal.component(.hour, from: t)
                if h >= 20 || h < 10 { return true }
                t = t.addingTimeInterval(30 * 60)
            }
            return cal.component(.hour, from: ses.end) >= 20 || cal.component(.hour, from: ses.end) < 10
        }
        let nightIdx = sessions.indices
            .filter { overlapsNight(sessions[$0]) }
            .max { sessions[$0].end.timeIntervalSince(sessions[$0].start)
                 < sessions[$1].end.timeIntervalSince(sessions[$1].start) }

        var out: [NapSummary] = []
        for (i, ses) in sessions.enumerated() {
            if i == nightIdx { continue }
            // Chỉ nhận giấc nằm ban ngày (bắt đầu ~08h–20h) và cùng ngày `date`.
            let h = cal.component(.hour, from: ses.start)
            guard (8..<20).contains(h), cal.isDate(ses.start, inSameDayAs: date) else { continue }
            out.append(NapSummary(start: ses.start, end: ses.end,
                                  stages: ses.stages.isEmpty ? nil : ses.stages))
        }
        return out.sorted { $0.start < $1.start }
    }

    private static func napStage(_ value: Int) -> SleepStage? {
        switch value {
        case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
        case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
        case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
             HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .light
        default: return nil
        }
    }

    // MARK: - Theo dõi nền (đánh thức app khi có phiên ngủ mới)

    /// Đăng ký `HKObserverQuery` + background delivery cho dữ liệu ngủ: khi nguồn ghi phiên ngủ mới,
    /// iOS đánh thức app nền → gọi `onUpdate` để quét + lưu giấc trưa. Bọc guard, không crash khi
    /// chưa quyền / trên simulator (enableBackgroundDelivery có thể lặng lẽ thất bại — không sao).
    func startObservingSleep(onUpdate: @escaping @Sendable () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completion, error in
            if error == nil { onUpdate() }
            completion()
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { _, _ in }
    }

    // MARK: - Nhịp tim nghỉ

    func restingHeartRate(for date: Date) async throws -> Double? {
        let (start, end) = dayRange(date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: restingHRType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: store).first else { return nil }
        return sample.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
    }

    // MARK: - Nhịp tim theo giờ trong ngày (intraday)

    /// Lấy tất cả mẫu `heartRate` trong ngày để vẽ biểu đồ nhịp theo giờ (chế độ Ngày).
    func intradayHeartRate(for date: Date) async throws -> [(time: Date, bpm: Double)]? {
        let (start, end) = dayRange(date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: heartRateType, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .forward)],
            limit: HKObjectQueryNoLimit
        )
        let samples = try await descriptor.result(for: store)
        guard !samples.isEmpty else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return samples.map { ($0.startDate, $0.quantity.doubleValue(for: unit)) }
    }

    /// Dải thấp–cao mỗi ngày tính bằng `HKStatisticsCollectionQuery` (một truy vấn cho cả khoảng),
    /// chính xác hơn và nhẹ hơn cách lặp intraday từng ngày; nhịp nghỉ lấy riêng theo ngày.
    func heartRateDailyRanges(from: Date, to: Date) async throws -> [(date: Date, min: Double, max: Double, resting: Double?)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: from)
        guard let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: to)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let unit = HKUnit.count().unitDivided(by: .minute())

        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: heartRateType, predicate: predicate),
            options: [.discreteMin, .discreteMax],
            anchorDate: start,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)

        // Nhịp tim nghỉ từng ngày (gom thành từ điển để ghép vào dải).
        var restingByDay: [Date: Double] = [:]
        for (d, v) in (try? await restingHeartRates(from: start, to: to)) ?? [] {
            restingByDay[cal.startOfDay(for: d)] = v
        }

        var out: [(date: Date, min: Double, max: Double, resting: Double?)] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let day = cal.startOfDay(for: stats.startDate)
            let resting = restingByDay[day]
            if let lo = stats.minimumQuantity()?.doubleValue(for: unit),
               let hi = stats.maximumQuantity()?.doubleValue(for: unit) {
                out.append((day, lo, hi, resting))
            } else if let r = resting {
                out.append((day, r, r, r))
            }
        }
        return out
    }

    // MARK: - Bước

    func steps(for date: Date) async throws -> Int? {
        let (start, end) = dayRange(date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum
        )
        guard let sum = try await descriptor.result(for: store)?.sumQuantity() else { return nil }
        return Int(sum.doubleValue(for: .count()).rounded())
    }

    // MARK: - Sinh hiệu đêm (nhịp thở, oxy máu) — trung bình trong khung đêm 18h → 12h

    func respiratoryRate(for date: Date) async throws -> Double? {
        try await nightAverage(respiratoryType, unit: .count().unitDivided(by: .minute()), date: date)
    }

    func oxygenSaturation(for date: Date) async throws -> Double? {
        // HealthKit lưu SpO2 dạng phân số 0…1 → đổi ra %.
        guard let v = try await nightAverage(oxygenType, unit: .percent(), date: date) else { return nil }
        return v * 100
    }

    /// Trung bình các mẫu trong khung đêm trước ngày `date` (18h hôm trước → 12h trưa), như `sleepDetail`.
    private func nightAverage(_ type: HKQuantityType, unit: HKUnit, date: Date) async throws -> Double? {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let start = cal.date(byAdding: .hour, value: -6, to: dayStart),
              let end = cal.date(byAdding: .hour, value: 12, to: dayStart) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .discreteAverage
        )
        return try await descriptor.result(for: store)?.averageQuantity()?.doubleValue(for: unit)
    }

    // MARK: - Vận động trong ngày (quãng đường, calo, bước theo giờ)

    func distanceKm(for date: Date) async throws -> Double? {
        try await daySum(distanceType, unit: .meterUnit(with: .kilo), date: date)
    }

    func activeEnergyKcal(for date: Date) async throws -> Double? {
        try await daySum(activeEnergyType, unit: .kilocalorie(), date: date)
    }

    private func daySum(_ type: HKQuantityType, unit: HKUnit, date: Date) async throws -> Double? {
        let (start, end) = dayRange(date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        return try await descriptor.result(for: store)?.sumQuantity()?.doubleValue(for: unit)
    }

    /// Bước theo từng giờ bằng `HKStatisticsCollectionQuery` (khoảng 1 giờ).
    func hourlySteps(for date: Date) async throws -> [(hour: Int, steps: Int)] {
        let (start, end) = dayRange(date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: stepType, predicate: predicate),
            options: .cumulativeSum,
            anchorDate: start,
            intervalComponents: DateComponents(hour: 1)
        )
        let collection = try await descriptor.result(for: store)
        let cal = Calendar.current
        var out: [(hour: Int, steps: Int)] = []
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            guard let sum = stats.sumQuantity() else { return }
            out.append((cal.component(.hour, from: stats.startDate), Int(sum.doubleValue(for: .count()).rounded())))
        }
        return out
    }

    // MARK: - Cân nặng

    func latestBodyMass() async throws -> (kg: Double, date: Date)? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMassType)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: store).first else { return nil }
        return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.startDate)
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg)
        let sample = HKQuantitySample(type: bodyMassType, quantity: quantity, start: date, end: date)
        try await store.save(sample)
    }

    // MARK: - Helpers

    private func dayRange(_ date: Date) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}

import Foundation

/// Đọc dữ liệu thật từ **Google Health API v4beta** (`health.googleapis.com`).
/// Xác thực qua `GoogleAuth` (OAuth PKCE, token trong Keychain, tự làm mới).
///
/// Cách lấy: `dataPoints:dailyRollUp` cho bước/cân/nhịp tim nghỉ/HRV (đã kiểm với discovery doc
/// của API); ngủ và nhiệt độ da lấy best-effort qua `dataPoints` (list) — cần xác minh với số
/// thật trên iPhone của bạn .
final class GoogleHealthProvider: HealthStoreProvider, @unchecked Sendable {
    private let base = "https://health.googleapis.com/v4beta/users/me/dataTypes"

    // Tên data type (đoạn path) — theo discovery doc health.googleapis.com v4beta.
    private enum DataType {
        static let steps = "steps"
        static let weight = "weight"
        static let restingHeartRate = "daily-resting-heart-rate"
        static let hrv = "daily-heart-rate-variability"
        static let sleep = "sleep"
        static let skinTemp = "daily-sleep-temperature-derivations"
        /// Nhịp tim theo giờ/khoảng trong ngày — tên data type + định dạng trả về CHƯA xác minh
        /// với số thật trên iPhone; dùng best-effort, parse không ra thì trả nil (không bịa số).
        static let heartRate = "heart-rate"
        // T-020 — tên + trường lấy từ discovery doc v4beta (DailyRespiratoryRate, DailyOxygenSaturation,
        // DistanceRollupValue, ActiveEnergyBurnedRollupValue, StepsRollupValue). Chưa thử với số thật.
        static let respiratoryRate = "daily-respiratory-rate"
        static let oxygenSaturation = "daily-oxygen-saturation"
        static let distance = "distance"
        static let activeEnergy = "active-energy-burned"
    }

    enum ProviderError: LocalizedError {
        case notConnected
        var errorDescription: String? {
            switch self {
            case .notConnected: return "Chưa đăng nhập Google. Vào Cài đặt để đăng nhập."
            }
        }
    }

    // MARK: - Quyền

    func authorizationRequestNeeded() async -> Bool {
        await !GoogleAuth.shared.isConnected
    }

    func requestAuthorization() async throws {
        let clientID = await AppSettings.shared.googleClientID
        try await GoogleAuth.shared.signIn(clientID: clientID)
    }

    // MARK: - Các chỉ số (dailyRollUp cho 1 ngày)

    func steps(for date: Date) async throws -> Int? {
        guard let day = try await rollUp(DataType.steps, date: date) else { return nil }
        if let s = (day["steps"] as? [String: Any])?["countSum"] as? String, let n = Int(s) { return n }
        return nil
    }

    func latestBodyMass() async throws -> (kg: Double, date: Date)? {
        // Thử vài ngày gần nhất, lấy lần cân gần nhất có số.
        let cal = Calendar.current
        for back in 0..<7 {
            guard let d = cal.date(byAdding: .day, value: -back, to: date0()) else { continue }
            if let day = try await rollUp(DataType.weight, date: d),
               let grams = (day["weight"] as? [String: Any])?["weightGramsAvg"] as? Double {
                return (grams / 1000, d)
            }
        }
        return nil
    }

    func restingHeartRate(for date: Date) async throws -> Double? {
        guard let day = try await rollUp(DataType.restingHeartRate, date: date),
              let range = day["restingHeartRatePersonalRange"] as? [String: Any] else { return nil }
        return midpoint(range, "beatsPerMinuteMin", "beatsPerMinuteMax")
    }

    func heartRateVariability(for date: Date) async throws -> Double? {
        guard let day = try await rollUp(DataType.hrv, date: date),
              let range = day["heartRateVariabilityPersonalRange"] as? [String: Any] else { return nil }
        return midpoint(range,
                        "averageHeartRateVariabilityMillisecondsMin",
                        "averageHeartRateVariabilityMillisecondsMax")
    }

    func saveBodyMass(kg: Double, date: Date) async throws {
        // Google Health là nguồn chỉ-đọc trong app này; ghi cân vẫn qua Apple Health.
        throw ProviderError.notConnected
    }

    // MARK: - Ngủ + nhiệt độ da (best-effort qua list dataPoints)

    func sleepSummary(for date: Date) async throws -> SleepSummary? {
        // Ưu tiên suy từ chi tiết (có giai đoạn + lấp khoảng thức) để màn Hôm nay KHỚP màn chi tiết.
        if let d = try? await sleepDetail(for: date), !d.segments.isEmpty {
            return d.summary
        }
        // Dự phòng: tóm tắt Fitbit khi không lấy được giai đoạn.
        guard let points = try? await listDataPoints(DataType.sleep, date: date) else { return nil }
        // Lấy phiên ngủ chính (main_sleep) hoặc dài nhất.
        var best: (mins: Double, awakeMins: Double, start: Date?, end: Date?, awakeCount: Int)?
        for p in points {
            guard let sleep = p["sleep"] as? [String: Any] else { continue }
            let summary = sleep["summary"] as? [String: Any]
            let asleep = doubleString(summary?["minutesAsleep"]) ?? 0
            let awake = doubleString(summary?["minutesAwake"]) ?? 0
            let interval = sleep["interval"] as? [String: Any]
            let start = isoDate(interval?["startTime"])
            let end = isoDate(interval?["endTime"])
            let awakeCount = (sleep["stages"] as? [[String: Any]])?
                .filter { ($0["type"] as? String)?.uppercased() == "AWAKE" }.count ?? 0
            if best == nil || asleep > best!.mins {
                best = (asleep, awake, start, end, awakeCount)
            }
        }
        guard let b = best, b.mins > 0 else { return nil }
        return SleepSummary(totalHours: b.mins / 60, awakeCount: b.awakeCount, bedTime: b.start, wakeTime: b.end)
    }

    func sleepDetail(for date: Date) async throws -> SleepDetail? {
        guard let points = try? await listDataPoints(DataType.sleep, date: date) else { return nil }
        // Lấy phiên ngủ nhiều giai đoạn nhất (main sleep).
        var bestStages: [[String: Any]]?
        var bestCount = 0
        for p in points {
            guard let sleep = p["sleep"] as? [String: Any],
                  let stages = sleep["stages"] as? [[String: Any]] else { continue }
            if stages.count > bestCount { bestCount = stages.count; bestStages = stages }
        }
        guard let stages = bestStages else { return nil }
        let segments = stages.compactMap { st -> SleepSegment? in
            guard let start = isoDate(st["startTime"]), let end = isoDate(st["endTime"]), end > start,
                  let stage = mapStage(st["type"] as? String) else { return nil }
            return SleepSegment(stage: stage, start: start, end: end)
        }
        guard !segments.isEmpty else { return nil }
        // Lấp các khoảng trống giữa đoạn ngủ thành THỨC (Fitbit chỉ ghi đoạn có nhãn, bỏ trống lúc thức).
        return SleepDetail(segments: SleepDetail.fillingAwakeGaps(segments))
    }

    /// Best-effort giấc ngủ ngày từ Google Health v4beta: list phiên ngủ phủ CẢ ngày (±2h),
    /// loại phiên dài nhất (ngủ đêm chính), giữ các phiên bắt đầu ban ngày (~08h–20h).
    /// Định dạng v4beta CHƯA xác minh với số thật → mọi lỗi/không parse được đều trả `[]` (không bịa).
    func daytimeSleeps(for date: Date) async throws -> [NapSummary] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        guard let winStart = cal.date(byAdding: .hour, value: -2, to: dayStart),
              let winEnd = cal.date(byAdding: .hour, value: 26, to: dayStart) else { return [] }
        let f = ISO8601DateFormatter()
        let filter = "startTime >= \"\(f.string(from: winStart))\" AND startTime < \"\(f.string(from: winEnd))\""
        var comps = URLComponents(string: "\(base)/\(DataType.sleep)/dataPoints")!
        comps.queryItems = [.init(name: "filter", value: filter), .init(name: "pageSize", value: "50")]
        guard let url = comps.url,
              let json = try? await request(url.absoluteString, method: "GET", body: nil),
              let points = json["dataPoints"] as? [[String: Any]] else { return [] }

        var sessions: [(start: Date, end: Date)] = []
        for p in points {
            guard let sleep = p["sleep"] as? [String: Any],
                  let interval = sleep["interval"] as? [String: Any],
                  let s = isoDate(interval["startTime"]), let e = isoDate(interval["endTime"]), e > s else { continue }
            sessions.append((s, e))
        }
        guard !sessions.isEmpty else { return [] }
        // Phiên dài nhất = ngủ đêm chính → loại.
        let mainIdx = sessions.indices.max {
            sessions[$0].end.timeIntervalSince(sessions[$0].start)
                < sessions[$1].end.timeIntervalSince(sessions[$1].start)
        }
        var out: [NapSummary] = []
        for (i, ses) in sessions.enumerated() {
            if i == mainIdx { continue }
            let h = cal.component(.hour, from: ses.start)
            guard (8..<20).contains(h), cal.isDate(ses.start, inSameDayAs: date) else { continue }
            out.append(NapSummary(start: ses.start, end: ses.end, stages: nil))
        }
        return out.sorted { $0.start < $1.start }
    }

    private func mapStage(_ type: String?) -> SleepStage? {
        switch type?.uppercased() {
        case "AWAKE", "WAKE": return .awake
        case "DEEP": return .deep
        case "REM": return .rem
        case "LIGHT", "CORE", "ASLEEP": return .light
        default: return nil
        }
    }

    func skinTemperature(for date: Date) async throws -> Double? {
        guard let points = try? await listDataPoints(DataType.skinTemp, date: date) else { return nil }
        for p in points {
            guard let d = p["dailySleepTemperatureDerivations"] as? [String: Any] else { continue }
            if let nightly = d["nightlyTemperatureCelsius"] as? Double {
                let baseline = d["baselineTemperatureCelsius"] as? Double ?? nightly
                return nightly - baseline  // chênh lệch so với nền (°C)
            }
        }
        return nil
    }

    // MARK: - Nhịp tim theo giờ trong ngày (intraday)

    /// Thử lấy nhịp tim trong ngày qua `dataPoints` (list) cho kiểu dữ liệu nhịp tim.
    /// Định dạng trả về của Google Health API v4beta CHƯA được xác minh với số thật của bạn,
    /// nên mọi lỗi/không parse được đều trả `nil` an toàn để UI tự ẩn khối intraday.
    func intradayHeartRate(for date: Date) async throws -> [(time: Date, bpm: Double)]? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        let f = ISO8601DateFormatter()
        let filter = "startTime >= \"\(f.string(from: start))\" AND startTime < \"\(f.string(from: end))\""
        var comps = URLComponents(string: "\(base)/\(DataType.heartRate)/dataPoints")!
        comps.queryItems = [.init(name: "filter", value: filter), .init(name: "pageSize", value: "500")]
        guard let url = comps.url,
              let json = try? await request(url.absoluteString, method: "GET", body: nil),
              let points = json["dataPoints"] as? [[String: Any]] else { return nil }

        var out: [(time: Date, bpm: Double)] = []
        for p in points {
            // Thử các tên trường hay gặp; chưa chắc đúng với v4beta → bỏ qua điểm nào không parse được.
            let hr = (p["heartRate"] as? [String: Any]) ?? p
            let bpm = (hr["beatsPerMinute"] as? Double)
                ?? doubleString(hr["beatsPerMinute"])
                ?? (hr["bpm"] as? Double)
            let interval = p["interval"] as? [String: Any]
            let time = isoDate(interval?["startTime"]) ?? isoDate(p["startTime"])
            if let bpm, let time, bpm > 0 { out.append((time, bpm)) }
        }
        return out.isEmpty ? nil : out.sorted { $0.time < $1.time }
    }

    // MARK: - Sinh hiệu & vận động (T-020, best-effort — lỗi/không parse được → nil/[])

    /// Nhịp thở: kiểu "daily" (1 điểm/ngày, tính cho giấc ngủ chính) → lọc theo `daily_respiratory_rate.date`.
    func respiratoryRate(for date: Date) async throws -> Double? {
        guard let points = try? await listDaily(DataType.respiratoryRate, field: "daily_respiratory_rate", date: date)
        else { return nil }
        for p in points {
            if let v = doubleString((p["dailyRespiratoryRate"] as? [String: Any])?["breathsPerMinute"]), v > 0 {
                return v
            }
        }
        return nil
    }

    /// Oxy máu: kiểu "daily" → `dailyOxygenSaturation.averagePercentage` (trung bình lúc ngủ).
    func oxygenSaturation(for date: Date) async throws -> Double? {
        guard let points = try? await listDaily(DataType.oxygenSaturation, field: "daily_oxygen_saturation", date: date)
        else { return nil }
        for p in points {
            if let v = doubleString((p["dailyOxygenSaturation"] as? [String: Any])?["averagePercentage"]), v > 0 {
                return v
            }
        }
        return nil
    }

    /// Quãng đường: `dailyRollUp` → `distance.millimetersSum` (chuỗi int64, mm) → km.
    func distanceKm(for date: Date) async throws -> Double? {
        guard let day = try? await rollUp(DataType.distance, date: date),
              let mm = doubleString((day["distance"] as? [String: Any])?["millimetersSum"]) else { return nil }
        return mm / 1_000_000
    }

    /// Calo vận động: `dailyRollUp` → `activeEnergyBurned.kcalSum`.
    func activeEnergyKcal(for date: Date) async throws -> Double? {
        guard let day = try? await rollUp(DataType.activeEnergy, date: date) else { return nil }
        return doubleString((day["activeEnergyBurned"] as? [String: Any])?["kcalSum"])
    }

    /// Bước theo giờ: `dataPoints:rollUp` (giờ vật lý) với `windowSize = 3600s` cho cả ngày.
    func hourlySteps(for date: Date) async throws -> [(hour: Int, steps: Int)] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let f = ISO8601DateFormatter()
        let body: [String: Any] = [
            "range": ["startTime": f.string(from: start), "endTime": f.string(from: end)],
            "windowSize": "3600s",
        ]
        guard let json = try? await request("\(base)/\(DataType.steps)/dataPoints:rollUp", method: "POST", body: body),
              let points = json["rollupDataPoints"] as? [[String: Any]] else { return [] }
        var out: [(hour: Int, steps: Int)] = []
        for p in points {
            guard let t = isoDate(p["startTime"]),
                  let n = doubleString((p["steps"] as? [String: Any])?["countSum"]) else { continue }
            out.append((cal.component(.hour, from: t), Int(n)))
        }
        return out.sorted { $0.hour < $1.hour }
    }

    /// `dataPoints` (list) cho kiểu "daily": lọc `{field}.date` trong [date, date+1).
    private func listDaily(_ type: String, field: String, date: Date) async throws -> [[String: Any]] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let next = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        func iso(_ d: Date) -> String {
            let c = cal.dateComponents([.year, .month, .day], from: d)
            return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
        }
        let filter = "\(field).date >= \"\(iso(start))\" AND \(field).date < \"\(iso(next))\""
        var comps = URLComponents(string: "\(base)/\(type)/dataPoints")!
        comps.queryItems = [.init(name: "filter", value: filter), .init(name: "pageSize", value: "10")]
        let json = try await request(comps.url!.absoluteString, method: "GET", body: nil)
        return (json["dataPoints"] as? [[String: Any]]) ?? []
    }

    // MARK: - Gọi API

    /// `dataPoints:dailyRollUp` cho đúng 1 ngày `date` → trả rollupDataPoint đầu tiên.
    private func rollUp(_ type: String, date: Date) async throws -> [String: Any]? {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        let body: [String: Any] = [
            "range": [
                "start": ["date": ymd(start)],
                "end": ["date": ymd(end)],
            ],
            "windowSizeDays": 1,
        ]
        let json = try await request("\(base)/\(type)/dataPoints:dailyRollUp", method: "POST", body: body)
        return (json["rollupDataPoints"] as? [[String: Any]])?.first
    }

    /// `dataPoints` (list) lọc theo ngày — dùng cho ngủ / nhiệt độ da.
    private func listDataPoints(_ type: String, date: Date) async throws -> [[String: Any]] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let winStart = cal.date(byAdding: .hour, value: -6, to: start),
              let winEnd = cal.date(byAdding: .hour, value: 12, to: start) else { return [] }
        let f = ISO8601DateFormatter()
        let filter = "startTime >= \"\(f.string(from: winStart))\" AND startTime < \"\(f.string(from: winEnd))\""
        var comps = URLComponents(string: "\(base)/\(type)/dataPoints")!
        comps.queryItems = [.init(name: "filter", value: filter), .init(name: "pageSize", value: "50")]
        let json = try await request(comps.url!.absoluteString, method: "GET", body: nil)
        return (json["dataPoints"] as? [[String: Any]]) ?? []
    }

    private func request(_ urlString: String, method: String, body: [String: Any]?) async throws -> [String: Any] {
        let token = try await GoogleAuth.shared.validAccessToken()
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String } ?? "HTTP \(http.statusCode)"
            throw GoogleAuth.AuthError.server(msg)
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Helpers

    private func date0() -> Date { Date() }

    private func midpoint(_ dict: [String: Any], _ minKey: String, _ maxKey: String) -> Double? {
        guard let lo = dict[minKey] as? Double, let hi = dict[maxKey] as? Double else {
            return (dict[minKey] as? Double) ?? (dict[maxKey] as? Double)
        }
        return (lo + hi) / 2
    }

    private func doubleString(_ any: Any?) -> Double? {
        if let s = any as? String { return Double(s) }
        if let d = any as? Double { return d }
        return nil
    }

    private func isoDate(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }

    private func ymd(_ date: Date) -> [String: Int] {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return ["year": c.year ?? 2026, "month": c.month ?? 1, "day": c.day ?? 1]
    }
}

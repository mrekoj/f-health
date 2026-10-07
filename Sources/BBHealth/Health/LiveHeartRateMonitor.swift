import Foundation
import Observation
#if !targetEnvironment(simulator)
import CoreBluetooth
#endif

/// Nhịp tim **trực tiếp** qua Bluetooth từ vòng Fitbit Air (T-021).
///
/// Khi anh bật "Share heart rate / Chia sẻ nhịp tim" trên vòng, vòng phát nhịp tim theo chuẩn
/// Bluetooth Heart Rate Profile: service `0x180D`, characteristic Heart Rate Measurement `0x2A37`.
/// App đóng vai central: quét → kết nối → bật thông báo → nhận bpm ~1 lần/giây.
///
/// T-022: khi kết nối còn dò **tất cả** dịch vụ vòng mở qua Bluetooth chuẩn (để biết vòng thật
/// sự chia sẻ gì): pin `0x180F`, thông tin thiết bị `0x180A`, vị trí cảm biến `0x2A38`; và đọc đầy đủ
/// gói `0x2A37` (tiếp xúc da, khoảng nhịp RR) → tính HRV trực tiếp (RMSSD) nếu vòng gửi RR.
///
/// - Chỉ chạy khi app đang mở (foreground) — không bật chế độ nền.
/// - Trên simulator không có Bluetooth → sinh số giả 62–78 mỗi giây (+ pin, thông tin vòng, RR giả)
///   để xem/chụp màn hình.
@Observable
@MainActor
final class LiveHeartRateMonitor: NSObject {

    enum State: Equatable {
        case idle
        case bluetoothOff
        case unauthorized
        case scanning
        case connecting(String)
        case connected(String)
        case disconnected
        case unavailable
    }

    /// Một mẫu nhịp tim: thời điểm + bpm.
    struct Sample: Identifiable, Equatable {
        let time: Date
        let bpm: Int
        var id: Date { time }
    }

    /// Một dịch vụ Bluetooth vòng mở: UUID + tên tiếng Việt (nếu biết).
    struct ServiceInfo: Identifiable, Equatable {
        let uuid: String
        let name: String
        var id: String { uuid }
    }

    /// Một khoảng nhịp RR (mili giây) kèm thời điểm nhận.
    struct RRSample: Equatable {
        let time: Date
        let ms: Double
    }

    /// Một điểm HRV trực tiếp (RMSSD, ms) để vẽ đường nhỏ.
    struct HRVPoint: Identifiable, Equatable {
        let time: Date
        let rmssd: Double
        var id: Date { time }
    }

    /// Kết quả đọc 1 gói Heart Rate Measurement (0x2A37).
    struct Measurement: Equatable {
        let bpm: Int
        /// Vòng có hỗ trợ báo tiếp xúc da không (bit2).
        let contactSupported: Bool
        /// Đang chạm da (bit1) — chỉ có nghĩa khi `contactSupported`.
        let contactDetected: Bool?
        /// Năng lượng tiêu hao (kJ) nếu có — app không dùng.
        let energyExpended: Int?
        /// Các khoảng RR trong gói, đã đổi ra mili giây.
        let rrMs: [Double]
    }

    private(set) var state: State = .idle
    /// Nhịp tim mới nhất (lần/phút).
    private(set) var bpm: Int?
    /// Các mẫu gần đây (giữ ~10 phút).
    private(set) var samples: [Sample] = []
    /// Lúc bắt đầu phiên (mẫu đầu tiên).
    private(set) var sessionStart: Date?
    private(set) var lastUpdate: Date?
    // Thống kê cả phiên (không bị cắt theo cửa sổ 10 phút).
    private(set) var sessionMin: Int?
    private(set) var sessionMax: Int?
    private var sessionSum = 0
    private var sessionCount = 0

    // MARK: Thông tin vòng (T-022)

    /// Các dịch vụ vòng mở (nil = chưa dò xong).
    private(set) var discoveredServices: [ServiceInfo]?
    /// Pin vòng (%), nil = chưa đọc / vòng không chia sẻ.
    private(set) var batteryPercent: Int?
    /// Tên vòng quảng bá qua Bluetooth (vd "Fitbit Air") — dòng đầu mục Thiết bị (T-023).
    private(set) var deviceName: String?
    private(set) var manufacturer: String?
    private(set) var model: String?
    private(set) var firmware: String?
    private(set) var hardware: String?
    /// Vị trí cảm biến (tiếng Việt), vd "Cổ tay".
    private(set) var sensorLocation: String?
    /// Đã nhận ít nhất 1 gói nhịp tim (để biết các cờ tiếp xúc/RR đã có nghĩa chưa).
    private(set) var measurementSeen = false
    private(set) var contactSupported = false
    private(set) var contactDetected: Bool?
    /// Vòng có gửi RR trong phiên này không (giữ "có" khi đã thấy 1 lần).
    private(set) var rrPresent = false
    /// RR 2 phút gần nhất.
    private(set) var rrIntervals: [RRSample] = []
    /// HRV trực tiếp (RMSSD, ms) — cần ≥ 20 RR hợp lệ trong 60 giây gần nhất.
    private(set) var liveRMSSD: Double?
    /// Lịch sử RMSSD 2 phút gần nhất (vẽ đường nhỏ).
    private(set) var rmssdHistory: [HRVPoint] = []
    /// Đang đọc thông tin vòng (dò dịch vụ / chờ đọc pin, thông tin thiết bị…).
    private(set) var infoReading = false

    var rrIntervalsMs: [Double] { rrIntervals.map(\.ms) }

    /// Giữ RR / lịch sử HRV trong bao lâu (giây).
    private let rrWindow: TimeInterval = 2 * 60
    /// Cửa sổ tính RMSSD (giây) + số RR tối thiểu.
    private let rmssdWindow: TimeInterval = 60
    private let rmssdMinCount = 20
    /// Tính lại RMSSD cách nhau ít nhất (giây).
    private let rmssdEvery: TimeInterval = 3
    private var lastRMSSDTime: Date?

    /// Số mẫu cả phiên (để lưu `LiveSession`).
    var sessionSampleCount: Int { sessionCount }

    var sessionAverage: Int? {
        sessionCount > 0 ? Int((Double(sessionSum) / Double(sessionCount)).rounded()) : nil
    }

    /// Giữ mẫu trong bao lâu (giây).
    private let keepWindow: TimeInterval = 10 * 60

    #if targetEnvironment(simulator)
    private var timer: Timer?
    private var fakeValue = 70.0
    /// Bài thở đang chạy (sim): nhịp giả hạ dần ~80 → ~66 + lên xuống theo hơi thở.
    private var calmStart: Date?
    private var calmTau: TimeInterval = 100
    private var calmCycle: TimeInterval = 10
    /// Các pha của bài thở đang chạy (T-024) — để nhịp giả chững lại khi giữ hơi.
    private var calmPhases: [BreathPhase] = []
    /// Thời gian (ms) chưa "đủ 1 nhịp" để sinh RR giả.
    private var fakeRRDebt = 0.0
    #else
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var hrCharacteristic: CBCharacteristic?
    /// Số lần tự kết nối lại sau khi rớt (tối đa 2).
    private var reconnectAttempts = 0
    private let maxReconnects = 2
    /// Đang dừng chủ động → rớt kết nối không tính là lỗi.
    private var stopping = false
    /// Chờ ngắn khi quét để ưu tiên thiết bị tên "Fitbit".
    private var fallbackCandidate: CBPeripheral?
    private var fallbackTask: Task<Void, Never>?
    private var fallbackName: String?
    /// Dịch vụ còn chờ dò đặc tính / đặc tính còn chờ đọc (để biết "đang đọc…" xong chưa).
    private var pendingServices: Set<CBUUID> = []
    private var pendingReads: Set<CBUUID> = []
    /// Hết giờ chờ đọc thông tin (có vòng không trả lời một số lệnh đọc).
    private var infoTimeoutTask: Task<Void, Never>?

    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")
    static let bodySensorLocation = CBUUID(string: "2A38")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInfoService = CBUUID(string: "180A")
    static let manufacturerName = CBUUID(string: "2A29")
    static let modelNumber = CBUUID(string: "2A24")
    static let firmwareRevision = CBUUID(string: "2A26")
    static let hardwareRevision = CBUUID(string: "2A27")
    #endif

    // MARK: - Điều khiển

    func start() {
        resetSession()
        resetDeviceInfo()
        #if targetEnvironment(simulator)
        startSimulated()
        #else
        stopping = false
        reconnectAttempts = 0
        if let central {
            handleCentralState(central.state)
        } else {
            // queue nil = main queue → delegate chạy trên main thread.
            central = CBCentralManager(delegate: self, queue: nil)
        }
        #endif
    }

    func stop() {
        #if targetEnvironment(simulator)
        timer?.invalidate()
        timer = nil
        infoReading = false
        state = .idle
        #else
        stopping = true
        fallbackTask?.cancel()
        fallbackTask = nil
        fallbackCandidate = nil
        infoTimeoutTask?.cancel()
        infoTimeoutTask = nil
        infoReading = false
        if let p = peripheral {
            if let c = hrCharacteristic, p.state == .connected { p.setNotifyValue(false, for: c) }
            central?.cancelPeripheralConnection(p)
        }
        if central?.isScanning == true { central?.stopScan() }
        peripheral = nil
        hrCharacteristic = nil
        state = .idle
        #endif
    }

    /// Thử lại sau khi mất kết nối / lỗi.
    func retry() {
        stop()
        start()
    }

    // MARK: - Ghi mẫu

    private func resetSession() {
        bpm = nil
        samples = []
        sessionStart = nil
        lastUpdate = nil
        sessionMin = nil
        sessionMax = nil
        sessionSum = 0
        sessionCount = 0
    }

    /// Xoá thông tin vòng khi bắt đầu phiên mới (kết nối lại tự động thì giữ).
    private func resetDeviceInfo() {
        discoveredServices = nil
        batteryPercent = nil
        deviceName = nil
        manufacturer = nil
        model = nil
        firmware = nil
        hardware = nil
        sensorLocation = nil
        measurementSeen = false
        contactSupported = false
        contactDetected = nil
        rrPresent = false
        rrIntervals = []
        liveRMSSD = nil
        rmssdHistory = []
        lastRMSSDTime = nil
        infoReading = false
    }

    /// Ghi 1 gói đo đầy đủ: bpm + tiếp xúc da + RR.
    private func record(_ m: Measurement, at time: Date = Date()) {
        measurementSeen = true
        contactSupported = m.contactSupported
        contactDetected = m.contactSupported ? m.contactDetected : nil
        record(m.bpm, at: time)
        if !m.rrMs.isEmpty { recordRR(m.rrMs, at: time) }
    }

    /// Lưu RR (2 phút gần nhất) và tính lại RMSSD mỗi vài giây.
    private func recordRR(_ values: [Double], at time: Date) {
        rrPresent = true
        rrIntervals.append(contentsOf: values.map { RRSample(time: time, ms: $0) })
        let cutoff = time.addingTimeInterval(-rrWindow)
        if let first = rrIntervals.first, first.time < cutoff {
            rrIntervals.removeAll { $0.time < cutoff }
        }
        if let last = lastRMSSDTime, time.timeIntervalSince(last) < rmssdEvery { return }
        lastRMSSDTime = time
        let windowStart = time.addingTimeInterval(-rmssdWindow)
        let recent = rrIntervals.filter { $0.time >= windowStart }.map(\.ms)
        liveRMSSD = Self.rmssd(recent, minCount: rmssdMinCount)
        if let v = liveRMSSD {
            rmssdHistory.append(HRVPoint(time: time, rmssd: v))
        }
        if let first = rmssdHistory.first, first.time < cutoff {
            rmssdHistory.removeAll { $0.time < cutoff }
        }
    }

    /// RMSSD = căn bậc hai trung bình bình phương chênh lệch giữa các RR liên tiếp.
    /// Bỏ RR ngoài 300–2000 ms (nhiễu / nhịp hụt). Không đủ `minCount` RR → nil.
    nonisolated static func rmssd(_ rr: [Double], minCount: Int = 20) -> Double? {
        let clean = rr.filter { $0 >= 300 && $0 <= 2000 }
        guard clean.count >= minCount, clean.count >= 2 else { return nil }
        var sum = 0.0
        for i in 1..<clean.count {
            let d = clean[i] - clean[i - 1]
            sum += d * d
        }
        return (sum / Double(clean.count - 1)).squareRoot()
    }

    private func record(_ value: Int, at time: Date = Date()) {
        // Bỏ số vô lý (0 = vòng chưa đo được da).
        guard value >= 25, value <= 240 else { return }
        bpm = value
        lastUpdate = time
        if sessionStart == nil { sessionStart = time }
        samples.append(Sample(time: time, bpm: value))
        let cutoff = time.addingTimeInterval(-keepWindow)
        if let first = samples.first, first.time < cutoff {
            samples.removeAll { $0.time < cutoff }
        }
        sessionMin = min(sessionMin ?? value, value)
        sessionMax = max(sessionMax ?? value, value)
        sessionSum += value
        sessionCount += 1
    }

    // MARK: - Đọc gói Heart Rate Measurement (chuẩn Bluetooth)

    /// Byte 0 = cờ:
    /// - bit0: 1 → bpm UInt16 little-endian, 0 → UInt8
    /// - bit1–2: tiếp xúc da (bit2 = vòng hỗ trợ báo, bit1 = đang chạm da)
    /// - bit3: có năng lượng tiêu hao (UInt16, kJ)
    /// - bit4: có các khoảng RR (mỗi cái UInt16, đơn vị 1/1024 giây)
    nonisolated static func parseMeasurement(_ data: Data) -> Measurement? {
        let bytes = [UInt8](data)
        guard let flags = bytes.first else { return nil }
        var i = 1
        func u16() -> Int? {
            guard i + 1 < bytes.count else { return nil }
            let v = Int(UInt16(bytes[i]) | (UInt16(bytes[i + 1]) << 8))
            i += 2
            return v
        }
        let bpm: Int
        if flags & 0x01 == 0 {
            guard bytes.count >= 2 else { return nil }
            bpm = Int(bytes[1])
            i = 2
        } else {
            guard let v = u16() else { return nil }
            bpm = v
        }
        let supported = flags & 0x04 != 0
        let detected: Bool? = supported ? (flags & 0x02 != 0) : nil
        var energy: Int?
        if flags & 0x08 != 0 { energy = u16() }
        var rr: [Double] = []
        if flags & 0x10 != 0 {
            while let v = u16() { rr.append(Double(v) * 1000.0 / 1024.0) }
        }
        return Measurement(bpm: bpm, contactSupported: supported, contactDetected: detected,
                           energyExpended: energy, rrMs: rr)
    }

    /// Chỉ lấy bpm (giữ cho chỗ khác dùng).
    nonisolated static func parseHeartRate(_ data: Data) -> Int? {
        parseMeasurement(data)?.bpm
    }

    // MARK: - Tên dịch vụ / vị trí cảm biến (tiếng Việt)

    /// Tên tiếng Việt cho UUID dịch vụ Bluetooth chuẩn; dịch vụ riêng của hãng → mô tả chung.
    nonisolated static func serviceName(_ uuid: String) -> String {
        switch uuid.uppercased() {
        case "1800": return "Thông tin chung (hệ thống)"
        case "1801": return "Báo thay đổi (hệ thống)"
        case "180D": return "Nhịp tim"
        case "180F": return "Pin"
        case "180A": return "Thông tin thiết bị"
        case "1805": return "Giờ hiện tại"
        case "1809": return "Nhiệt độ cơ thể"
        case "1814": return "Tốc độ chạy bộ"
        case "1816": return "Tốc độ đạp xe"
        case "181C": return "Hồ sơ người dùng"
        case "181D": return "Cân nặng"
        case "1822": return "Ô-xy trong máu"
        case "1826": return "Máy tập thể dục"
        case "FE2C": return "Ghép nhanh của Google"
        case "FE9F": return "Dịch vụ của Google"
        default:
            return uuid.count > 8 ? "Dịch vụ riêng của hãng" : "Chưa rõ"
        }
    }

    /// Body Sensor Location (0x2A38) → tiếng Việt.
    nonisolated static func sensorLocationName(_ code: UInt8) -> String {
        switch code {
        case 1: return "Ngực"
        case 2: return "Cổ tay"
        case 3: return "Ngón tay"
        case 4: return "Bàn tay"
        case 5: return "Dái tai"
        case 6: return "Bàn chân"
        default: return "Khác"
        }
    }

    // MARK: - Simulator: số giả

    #if targetEnvironment(simulator)
    private func startSimulated() {
        timer?.invalidate()
        state = .connected("Fitbit Air (giả lập)")
        // Thông tin vòng giả lập (T-022).
        deviceName = "Fitbit Air"
        if DebugOptions.simFullRing {
            // Vòng "đầy đủ" (pin, chạm da, RR) — để xem các hàng chỉ hiện khi vòng có.
            discoveredServices = ["1800", "1801", "180A", "180D", "180F"]
                .map { ServiceInfo(uuid: $0, name: Self.serviceName($0)) }
            batteryPercent = 93
            manufacturer = "Google"
            model = "Fitbit Air (giả lập)"
            firmware = "1.0"
            sensorLocation = Self.sensorLocationName(2)
        } else {
            // Giống Fitbit Air thật (đã xác minh): chỉ Nhịp tim + Thông tin thiết bị + dịch vụ riêng.
            discoveredServices = ["1800", "1801", "180A", "180D", "ABBAFF00-E56A-484C-B832-8B17CF6CBFE8"]
                .map { ServiceInfo(uuid: $0, name: Self.serviceName($0)) }
            manufacturer = "Fitbit"
            model = "67"
            firmware = "67.20001.253.2"
        }
        // Nạp sẵn ~3 phút lịch sử để sparkline có hình ngay khi chụp màn.
        let now = Date()
        for i in stride(from: 180, to: 0, by: -1) {
            record(nextFakeMeasurement(), at: now.addingTimeInterval(TimeInterval(-i)))
        }
        sessionStart = now.addingTimeInterval(-180)
        record(nextFakeMeasurement(), at: now)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.record(self.nextFakeMeasurement())
            }
        }
    }

    /// Gói giả: bpm êm (+ chạm da + RR quanh 60000/bpm ± nhiễu khi giả lập vòng đầy đủ).
    /// Mặc định giống Fitbit Air thật: chỉ có bpm.
    private func nextFakeMeasurement() -> Measurement {
        let bpm = nextFakeValue()
        guard DebugOptions.simFullRing else {
            return Measurement(bpm: bpm, contactSupported: false, contactDetected: nil,
                               energyExpended: nil, rrMs: [])
        }
        let base = 60000.0 / Double(bpm)
        fakeRRDebt += 1000
        var rr: [Double] = []
        while fakeRRDebt >= base {
            rr.append(base + Double.random(in: -55...55))
            fakeRRDebt -= base
        }
        return Measurement(bpm: bpm, contactSupported: true, contactDetected: true,
                           energyExpended: nil, rrMs: rr)
    }

    /// Dao động êm trong khoảng 62–78; khi bài thở chạy thì hạ dần ~80 → ~66.
    private func nextFakeValue() -> Int {
        if let calmStart {
            let t = Date().timeIntervalSince(calmStart)
            let trend = 66 + 15 * exp(-t / calmTau)
            // Hít vào tim nhanh lên, thở ra chậm lại; giữ hơi thì chững (T-024).
            let wave = calmPhases.isEmpty ? sin(2 * .pi * t / calmCycle) : Self.breathWave(calmPhases, at: t)
            let noise = calmPhases.contains { $0.kind.isHold } ? 1.0 : 0.7
            fakeValue = trend + 3.5 * wave + Double.random(in: -noise...noise)
            return Int(fakeValue.rounded())
        }
        fakeValue += Double.random(in: -1.6...1.6)
        fakeValue += (70 - fakeValue) * 0.05
        fakeValue = min(78, max(62, fakeValue))
        return Int(fakeValue.rounded())
    }

    /// Sóng nhịp tim giả theo pha thở (−1…1): hít vào lên, thở ra xuống; giữ sau hít thì chững rồi
    /// lệch xuống chút, giữ sau thở ra thì chững rồi nhích lên chút — cho giống người thật.
    private static func breathWave(_ phases: [BreathPhase], at t: TimeInterval) -> Double {
        let cycle = phases.reduce(0) { $0 + $1.seconds }
        guard cycle > 0 else { return 0 }
        func target(_ i: Int, from v: Double) -> Double {
            let p = phases[i]
            let next = phases[(i + 1) % phases.count].kind
            switch p.kind {
            case .inhale: return next == .inhaleTop ? 0.6 : 1
            case .inhaleTop: return 1
            case .exhale: return -1
            case .holdIn: return v - 0.6     // tim hơi chậm lại khi nín thở
            case .holdOut: return v + 0.4    // hơi nhanh lại khi chờ hít
            }
        }
        // Giá trị đầu vòng = cuối vòng trước (chạy 2 lượt cho ổn định).
        var v = -1.0
        for _ in 0..<2 { for i in phases.indices { v = target(i, from: v) } }
        let inCycle = t.truncatingRemainder(dividingBy: cycle)
        var acc = 0.0
        for i in phases.indices {
            let p = phases[i]
            let end = target(i, from: v)
            if inCycle < acc + p.seconds {
                let x = max(0, min(1, (inCycle - acc) / max(0.1, p.seconds)))
                let smooth = x * x * (3 - 2 * x)
                // Pha giữ: chững phần đầu, lệch dần ở nửa sau.
                let k = p.kind.isHold ? max(0, (x - 0.4) / 0.6) : smooth
                return v + (end - v) * k
            }
            v = end
            acc += p.seconds
        }
        return v
    }
    #endif

    // MARK: - Bài thở (T-023)

    /// Simulator: cho nhịp giả hạ dần ~80 → ~66 trong `duration` giây và lên xuống theo hơi thở
    /// theo các pha của bài (T-024: giữ hơi thì chững) để màn tóm tắt bài thở có ý nghĩa.
    /// Máy thật: không làm gì.
    func beginSimulatedCalming(over duration: TimeInterval, pattern: BreathingPattern) {
        #if targetEnvironment(simulator)
        calmStart = Date()
        calmTau = max(2, duration / 3)
        calmCycle = max(2, pattern.breathPeriod)
        calmPhases = pattern.phases
        #endif
    }

    func endSimulatedCalming() {
        #if targetEnvironment(simulator)
        if calmStart != nil { fakeValue = min(78, max(62, fakeValue)) }
        calmStart = nil
        calmPhases = []
        #endif
    }
}

// MARK: - CoreBluetooth (chỉ máy thật)

#if !targetEnvironment(simulator)
extension LiveHeartRateMonitor: CBCentralManagerDelegate, CBPeripheralDelegate {

    private func handleCentralState(_ s: CBManagerState) {
        switch s {
        case .poweredOn:
            beginScan()
        case .poweredOff:
            state = .bluetoothOff
        case .unauthorized:
            state = .unauthorized
        case .unsupported:
            state = .unavailable
        default:
            break   // .unknown / .resetting: chờ cập nhật tiếp theo
        }
    }

    private func beginScan() {
        guard let central, central.state == .poweredOn, !stopping else { return }
        // Vòng đã kết nối với iPhone (qua app khác) không còn quảng bá → lấy luôn nếu có.
        if let known = central.retrieveConnectedPeripherals(withServices: [Self.heartRateService])
            .sorted(by: { Self.isFitbit($0.name) && !Self.isFitbit($1.name) }).first {
            connect(known)
            return
        }
        state = .scanning
        fallbackCandidate = nil
        central.scanForPeripherals(withServices: [Self.heartRateService],
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func connect(_ p: CBPeripheral, advertisedName: String? = nil) {
        fallbackTask?.cancel()
        fallbackTask = nil
        central?.stopScan()
        peripheral = p
        if let n = p.name ?? advertisedName, !n.isEmpty { deviceName = n }
        p.delegate = self
        state = .connecting(Self.displayName(p.name))
        central?.connect(p, options: nil)
    }

    nonisolated static func isFitbit(_ name: String?) -> Bool {
        (name ?? "").localizedCaseInsensitiveContains("fitbit")
    }

    nonisolated static func displayName(_ name: String?) -> String {
        guard let n = name, !n.isEmpty else { return "vòng đeo tay" }
        return n
    }

    // MARK: CBCentralManagerDelegate

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let s = central.state
        MainActor.assumeIsolated { self.handleCentralState(s) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advName
        MainActor.assumeIsolated {
            guard self.peripheral == nil, !self.stopping else { return }
            if Self.isFitbit(name) {
                self.connect(peripheral, advertisedName: name)
            } else if self.fallbackCandidate == nil {
                // Thiết bị nhịp tim khác: chờ 3 giây xem có Fitbit không, không có thì lấy cái này.
                self.fallbackCandidate = peripheral
                self.fallbackName = name
                self.fallbackTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    guard let self, !Task.isCancelled, self.peripheral == nil,
                          let cand = self.fallbackCandidate else { return }
                    self.connect(cand, advertisedName: self.fallbackName)
                }
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            self.reconnectAttempts = 0
            if let n = peripheral.name, !n.isEmpty { self.deviceName = n }
            self.state = .connecting(Self.displayName(peripheral.name))
            self.beginInfoReading()
            // T-022: dò TẤT CẢ dịch vụ để biết vòng mở gì qua Bluetooth chuẩn.
            peripheral.discoverServices(nil)
        }
    }

    /// Bắt đầu đọc thông tin vòng; quá 10 giây mà có lệnh đọc chưa trả lời thì thôi chờ.
    private func beginInfoReading() {
        pendingServices = []
        pendingReads = []
        infoReading = true
        infoTimeoutTask?.cancel()
        infoTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self, !Task.isCancelled else { return }
            self.pendingServices = []
            self.pendingReads = []
            self.infoReading = false
        }
    }

    /// Hết dịch vụ chờ dò + hết đặc tính chờ đọc → xong.
    private func checkInfoDone() {
        guard discoveredServices != nil, pendingServices.isEmpty, pendingReads.isEmpty else { return }
        infoReading = false
        infoTimeoutTask?.cancel()
        infoTimeoutTask = nil
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated { self.handleDrop(peripheral) }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated { self.handleDrop(peripheral) }
    }

    /// Rớt kết nối: thử nối lại nhẹ 1–2 lần rồi báo "Mất kết nối".
    private func handleDrop(_ p: CBPeripheral) {
        hrCharacteristic = nil
        guard !stopping else { return }
        if reconnectAttempts < maxReconnects, let central {
            reconnectAttempts += 1
            state = .connecting(Self.displayName(p.name))
            central.connect(p, options: nil)
        } else {
            peripheral = nil
            infoTimeoutTask?.cancel()
            infoTimeoutTask = nil
            infoReading = false
            state = .disconnected
        }
    }

    // MARK: CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        MainActor.assumeIsolated {
            let services = peripheral.services ?? []
            self.discoveredServices = services.map {
                ServiceInfo(uuid: $0.uuid.uuidString, name: Self.serviceName($0.uuid.uuidString))
            }
            guard services.contains(where: { $0.uuid == Self.heartRateService }) else {
                self.infoReading = false
                self.state = .disconnected
                return
            }
            // Chỉ dò đặc tính của các dịch vụ app hiểu.
            let wanted: [CBUUID: [CBUUID]] = [
                Self.heartRateService: [Self.heartRateMeasurement, Self.bodySensorLocation],
                Self.batteryService: [Self.batteryLevel],
                Self.deviceInfoService: [Self.manufacturerName, Self.modelNumber,
                                         Self.firmwareRevision, Self.hardwareRevision],
            ]
            for service in services {
                guard let chars = wanted[service.uuid] else { continue }
                self.pendingServices.insert(service.uuid)
                peripheral.discoverCharacteristics(chars, for: service)
            }
            self.checkInfoDone()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            self.pendingServices.remove(service.uuid)
            let chars = service.characteristics ?? []
            if service.uuid == Self.heartRateService {
                guard let c = chars.first(where: { $0.uuid == Self.heartRateMeasurement }) else {
                    self.infoReading = false
                    self.state = .disconnected
                    return
                }
                self.hrCharacteristic = c
                peripheral.setNotifyValue(true, for: c)
                self.state = .connected(Self.displayName(peripheral.name))
            }
            for c in chars where c.uuid != Self.heartRateMeasurement {
                if c.properties.contains(.read) {
                    self.pendingReads.insert(c.uuid)
                    peripheral.readValue(for: c)
                }
                // Pin: nhận cập nhật khi đổi (nếu vòng cho phép).
                if c.uuid == Self.batteryLevel, c.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: c)
                }
            }
            self.checkInfoDone()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let uuid = characteristic.uuid
        let data = error == nil ? characteristic.value : nil
        MainActor.assumeIsolated {
            defer {
                if self.pendingReads.remove(uuid) != nil { self.checkInfoDone() }
            }
            guard let data, !data.isEmpty else { return }
            switch uuid {
            case Self.heartRateMeasurement:
                if let m = Self.parseMeasurement(data) { self.record(m) }
            case Self.batteryLevel:
                let v = Int(data[data.startIndex])
                if (0...100).contains(v) { self.batteryPercent = v }
            case Self.bodySensorLocation:
                self.sensorLocation = Self.sensorLocationName(data[data.startIndex])
            case Self.manufacturerName:
                self.manufacturer = Self.text(data)
            case Self.modelNumber:
                self.model = Self.text(data)
            case Self.firmwareRevision:
                self.firmware = Self.text(data)
            case Self.hardwareRevision:
                self.hardware = Self.text(data)
            default:
                break
            }
        }
    }

    /// Chuỗi UTF-8 từ đặc tính (bỏ ký tự 0 cuối, khoảng trắng); rỗng → nil.
    nonisolated static func text(_ data: Data) -> String? {
        let s = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\0")))
        return s.isEmpty ? nil : s
    }
}
#endif

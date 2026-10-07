import Foundation
import SwiftData

/// Một **phiên đo nhịp tim trực tiếp** đã lưu (T-023): đo thường ("đo") hoặc bài thở ("bài thở").
/// Lưu khi anh bấm Dừng / đóng màn (đo ≥ 30 giây) hoặc khi bài thở kết thúc.
@Model
final class LiveSession {
    var id: UUID
    var start: Date
    var end: Date
    var minBpm: Int
    var maxBpm: Int
    var avgBpm: Int
    var sampleCount: Int
    /// "đo" | "bài thở" (xem `LiveSession.Kind`).
    var kind: String
    /// Bài thở: nhịp TB 15 giây đầu / 30 giây cuối.
    var startBpm: Int?
    var endBpm: Int?
    var note: String

    init(id: UUID = UUID(), start: Date, end: Date, minBpm: Int, maxBpm: Int, avgBpm: Int,
         sampleCount: Int, kind: String, startBpm: Int? = nil, endBpm: Int? = nil, note: String = "") {
        self.id = id
        self.start = start
        self.end = end
        self.minBpm = minBpm
        self.maxBpm = maxBpm
        self.avgBpm = avgBpm
        self.sampleCount = sampleCount
        self.kind = kind
        self.startBpm = startBpm
        self.endBpm = endBpm
        self.note = note
    }

    enum Kind {
        static let measure = "đo"
        static let breathing = "bài thở"
    }

    var isBreathing: Bool { kind == Kind.breathing }
    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }

    /// Tạo phiên từ danh sách mẫu (time, bpm); rỗng → nil.
    static func make(from samples: [(time: Date, bpm: Int)], kind: String,
                     startBpm: Int? = nil, endBpm: Int? = nil, note: String = "") -> LiveSession? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let values = samples.map(\.bpm)
        let avg = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        return LiveSession(start: first.time, end: last.time,
                           minBpm: values.min() ?? avg, maxBpm: values.max() ?? avg, avgBpm: avg,
                           sampleCount: values.count, kind: kind,
                           startBpm: startBpm, endBpm: endBpm, note: note)
    }

    /// "m:ss" (hoặc "h:mm:ss").
    static func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Số liệu bài thở

/// Tính các con số cho màn tóm tắt bài thở (tách riêng để dễ kiểm).
enum BreathingStats {
    struct Point {
        let time: Date
        let bpm: Int
    }

    /// TB các mẫu trong `window` giây đầu (tính từ mẫu đầu). Bài ngắn (dừng sớm) → cửa sổ co lại
    /// còn 1/3 thời lượng để "đầu" và "cuối" không trùng nhau.
    static func startAverage(_ pts: [Point], window: TimeInterval = 15) -> Int? {
        guard let first = pts.first?.time, let last = pts.last?.time else { return nil }
        let w = min(window, max(1, last.timeIntervalSince(first) / 3))
        return average(pts.filter { $0.time.timeIntervalSince(first) <= w })
    }

    /// TB các mẫu trong `window` giây cuối (co lại như trên khi bài ngắn).
    static func endAverage(_ pts: [Point], window: TimeInterval = 30) -> Int? {
        guard let first = pts.first?.time, let last = pts.last?.time else { return nil }
        let w = min(window, max(1, last.timeIntervalSince(first) / 3))
        return average(pts.filter { last.timeIntervalSince($0.time) <= w })
    }

    /// Biên độ nhịp tim lên xuống theo hơi thở (lần/phút) trong `window` giây cuối:
    /// chia theo từng nhịp thở (`cycle` giây), lấy (cao − thấp) mỗi nhịp rồi trung bình — cách này
    /// không bị ảnh hưởng khi nhịp tim đang hạ dần. Ít hơn 2 nhịp thở đủ → khoảng cao−thấp cả cửa sổ.
    static func breathSwing(_ pts: [Point], cycle: TimeInterval, window: TimeInterval = 120) -> Double? {
        guard let last = pts.last?.time, cycle > 0 else { return nil }
        let recent = pts.filter { last.timeIntervalSince($0.time) <= window }
        guard recent.count >= 4, let first = recent.first?.time else { return nil }
        var buckets: [Int: [Int]] = [:]
        for p in recent {
            buckets[Int(p.time.timeIntervalSince(first) / cycle), default: []].append(p.bpm)
        }
        // Chỉ lấy nhịp thở có đủ mẫu (≥ 60% số giây của 1 nhịp, vì vòng gửi ~1 mẫu/giây).
        let need = max(3, Int(cycle * 0.6))
        let swings = buckets.values.filter { $0.count >= need }
            .compactMap { b -> Double? in
                guard let lo = b.min(), let hi = b.max() else { return nil }
                return Double(hi - lo)
            }
        if swings.count >= 2 { return swings.reduce(0, +) / Double(swings.count) }
        let values = recent.map(\.bpm)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return Double(hi - lo)
    }

    /// Độ lệch chuẩn (lần/phút) trong `window` giây cuối — hiện kèm cho ai muốn xem kỹ.
    static func standardDeviation(_ pts: [Point], window: TimeInterval = 120) -> Double? {
        guard let last = pts.last?.time else { return nil }
        let v = pts.filter { last.timeIntervalSince($0.time) <= window }.map { Double($0.bpm) }
        guard v.count >= 4 else { return nil }
        let mean = v.reduce(0, +) / Double(v.count)
        return (v.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(v.count)).squareRoot()
    }

    private static func average(_ pts: [Point]) -> Int? {
        guard !pts.isEmpty else { return nil }
        return Int((Double(pts.map(\.bpm).reduce(0, +)) / Double(pts.count)).rounded())
    }
}

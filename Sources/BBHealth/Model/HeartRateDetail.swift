import Foundation

/// Một điểm nhịp tim trong ngày (intraday): thời điểm + số nhịp.
struct HeartRatePoint: Identifiable {
    let time: Date
    let bpm: Double
    var id: Date { time }
}

/// Chi tiết nhịp tim của một ngày: nhịp nghỉ, các điểm trong ngày, và HRV (nếu nguồn có).
struct HeartRateDetail {
    /// Nhịp tim nghỉ (lần/phút) của ngày.
    let restingBpm: Double?
    /// Nhịp tim theo giờ trong ngày — rỗng nếu nguồn không có intraday.
    let intraday: [HeartRatePoint]
    /// Biến thiên nhịp tim (HRV, ms) đêm trước — thường chỉ nguồn Google có.
    let hrv: Double?

    var hasIntraday: Bool { !intraday.isEmpty }

    /// Nhịp cao nhất / thấp nhất trong ngày (từ intraday).
    var maxBpm: Double? { intraday.map(\.bpm).max() }
    var minBpm: Double? { intraday.map(\.bpm).min() }

    /// Điểm nhịp thấp nhất / cao nhất trong ngày (giữ cả giờ để đánh dấu trên biểu đồ).
    var minPoint: HeartRatePoint? { intraday.min(by: { $0.bpm < $1.bpm }) }
    var maxPoint: HeartRatePoint? { intraday.max(by: { $0.bpm < $1.bpm }) }
}

/// Dải nhịp tim của một ngày (cho chế độ Tuần/Tháng kiểu Google Health):
/// thấp nhất – cao nhất trong ngày + nhịp tim nghỉ (chấm tham chiếu).
struct HeartDayRange: Identifiable {
    let date: Date
    let min: Double
    let max: Double
    let resting: Double?
    var id: Date { date }
}

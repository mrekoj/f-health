import Foundation
import SwiftData

/// Ghi chú sự kiện gắn vào một thời điểm nhịp tim (vd "Họp căng thẳng", "Tập thể dục").
/// Anh chạm vào biểu đồ Ngày → ghi lại "lúc đó có chuyện gì" để sau này nhớ lại vì sao nhịp cao/thấp.
@Model
final class HeartEvent {
    var id: UUID
    /// Thời điểm trong ngày (giờ:phút) mà anh muốn ghi chú.
    var time: Date
    /// Nội dung ghi chú tiếng Việt.
    var note: String
    /// Nhịp tim (lần/phút) tại thời điểm đó, nếu biết — để hiện kèm trong danh sách.
    var bpm: Double?

    init(id: UUID = UUID(), time: Date, note: String, bpm: Double? = nil) {
        self.id = id
        self.time = time
        self.note = note
        self.bpm = bpm
    }
}

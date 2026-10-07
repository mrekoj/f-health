import Foundation
import SwiftData

/// Tóm tắt **một giấc ngủ ngày / ngủ trưa** đọc từ nguồn (Fitbit → Apple/Google Health).
///
/// GIỚI HẠN KỸ THUẬT: app chỉ "thấy" được giấc trưa nếu nguồn (vòng Fitbit) đã **ghi phiên ngủ**
/// đó rồi đồng bộ sang Apple/Google Health. Giấc rất ngắn (vài phút chợp mắt) thường **không được
/// thiết bị ghi** → sẽ không có dữ liệu. Ta làm best-effort đúng kỹ thuật, không bịa số.
struct NapSummary: Equatable {
    /// Giờ bắt đầu giấc.
    let start: Date
    /// Giờ kết thúc giấc.
    let end: Date
    /// Phút mỗi giai đoạn (nếu nguồn có phân giai đoạn) — thường nil với giấc trưa ngắn.
    var stages: [SleepStage: Int]?
    /// `true` = giấc **suy ra từ nhịp tim** (Fitbit không ghi phiên ngủ) → độ dài/chất lượng chỉ gần đúng.
    /// `false` = giấc đọc từ **phiên ngủ thật** của Fitbit (chính xác hơn).
    var estimated: Bool = false

    /// Độ dài giấc (phút), làm tròn.
    var minutes: Int { max(0, Int((end.timeIntervalSince(start) / 60).rounded())) }

    /// Hai giấc có **chồng lấn khung giờ** không (để chống trùng giữa phiên-ngủ và HR-dò).
    func overlaps(_ other: NapSummary) -> Bool { overlaps(start: other.start, end: other.end) }
    /// Có chồng lấn với khoảng `[start, end]` bất kỳ không (vd một `NapLog` đã lưu).
    func overlaps(start otherStart: Date, end otherEnd: Date) -> Bool {
        start < otherEnd && otherStart < end
    }
}

/// Nhật ký **một giấc ngủ trưa đã lưu tự động** (SwiftData). App tự quét từ nguồn và chèn vào đây,
/// không cần anh ghi tay. `note` là câu đánh giá chất lượng theo độ dài + giờ ngủ (gắn hồ sơ của bạn).
@Model
final class NapLog {
    /// Khoá chống trùng theo thời điểm (so khớp `start` lệch ≤ 10 phút khi quét lại).
    var id: UUID
    var start: Date
    var end: Date
    var minutes: Int
    /// Nguồn đã phát hiện giấc (vd "Sức khoẻ", "Google Health", "Ước tính từ nhịp tim").
    var source: String
    /// `true` = giấc **ước tính từ nhịp tim** (Fitbit bỏ sót phiên ngủ) → độ dài chỉ gần đúng.
    /// Giá trị mặc định `false` để SwiftData tự migrate nhẹ cho dữ liệu cũ (toàn bộ là giấc phiên-ngủ thật).
    var estimated: Bool = false
    /// Câu đánh giá đời thường (từ `Explanations.napNote`).
    var note: String
    /// Thời điểm app lưu lại mục này.
    var loggedAt: Date

    init(start: Date, end: Date, minutes: Int, source: String, note: String,
         estimated: Bool = false, loggedAt: Date = Date(), id: UUID = UUID()) {
        self.id = id
        self.start = start
        self.end = end
        self.minutes = minutes
        self.source = source
        self.estimated = estimated
        self.note = note
        self.loggedAt = loggedAt
    }

    /// Mức chất lượng để nhuộm màu chip (theo độ dài giấc).
    var level: MetricLevel { Explanations.napLevel(minutes: minutes) }
    /// Nhãn chip ngắn ("Lý tưởng" / "Hơi dài"…).
    var quality: String { Explanations.napQuality(minutes: minutes) }
}

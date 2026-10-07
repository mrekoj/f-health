import Foundation
import SwiftData

/// **Bài phân tích của AI** cho một kỳ báo cáo (T-026) — lưu lại để mở báo cáo lần sau không phải gọi AI
/// (đỡ tốn lượt miễn phí). Khoá theo (loại kỳ, ngày cuối kỳ).
@Model
final class AIAnalysis {
    var id: UUID
    /// `ReportKind.rawValue`.
    var kindRaw: String
    /// Ngày cuối kỳ (đầu ngày).
    var periodEnd: Date
    /// "Google Gemini", "Claude (Anthropic)"…
    var provider: String
    var model: String
    var text: String
    var createdAt: Date
    /// "quick" (mặc định) | "deep" (Phân tích sâu, model mạnh) — default để migrate nhẹ.
    var mode: String = "quick"

    init(kind: ReportKind, periodEnd: Date, provider: String, model: String, text: String, mode: String = "quick", createdAt: Date = Date()) {
        self.mode = mode
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.periodEnd = periodEnd
        self.provider = provider
        self.model = model
        self.text = text
        self.createdAt = createdAt
    }

    /// Bài mới nhất của một kỳ.
    static func latest(for period: ReportPeriod, mode: String = "quick", in context: ModelContext) -> AIAnalysis? {
        let raw = period.kind.rawValue
        let end = period.end
        var d = FetchDescriptor<AIAnalysis>(predicate: #Predicate { $0.kindRaw == raw && $0.periodEnd == end && $0.mode == mode },
                                            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }
}

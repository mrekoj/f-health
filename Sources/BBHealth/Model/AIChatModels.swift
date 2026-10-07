import Foundation
import SwiftData

/// Một lượt chat đã lưu (T-027). `contextKey` = kỳ báo cáo ("week|2026-10-05") hoặc màn gọi ("sleep|…").
@Model
final class AIChatMessage {
    var id: UUID
    var contextKey: String
    /// "user" | "assistant"
    var role: String
    var text: String
    var createdAt: Date

    init(contextKey: String, role: String, text: String, createdAt: Date = Date()) {
        self.id = UUID()
        self.contextKey = contextKey
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }

    static func history(for key: String, in context: ModelContext) -> [AIChatMessage] {
        let d = FetchDescriptor<AIChatMessage>(predicate: #Predicate { $0.contextKey == key },
                                               sortBy: [SortDescriptor(\.createdAt)])
        return (try? context.fetch(d)) ?? []
    }

    static func clear(_ key: String, in context: ModelContext) {
        for m in history(for: key, in: context) { context.delete(m) }
        try? context.save()
    }
}

/// Chạy vòng hội thoại có công cụ: gọi AI → nếu AI xin công cụ thì chạy rồi gửi kết quả → lặp (tối đa 6 vòng).
@MainActor
final class AIConversationRunner {
    enum Event { case text(String); case status(String?) }

    let client: any AIClient
    let tools: HealthDataTools?
    let system: String

    init(client: any AIClient, tools: HealthDataTools?, system: String) {
        self.client = client; self.tools = tools; self.system = system
    }

    /// `history` = các lượt trước (chỉ chữ). Trả về chữ cuối cùng của AI qua `onEvent`.
    func run(history: [AIMessage], onEvent: @escaping (Event) -> Void) async throws -> String {
        var messages = history
        let specs = (tools != nil && client.supportsTools) ? HealthDataTools.specs : []
        var finalText = ""
        for round in 0..<6 {
            var text = ""
            var calls: [AIToolCall] = []
            var raw: String?
            for try await ev in client.stream(system: system, messages: messages, tools: specs, maxTokens: 4096) {
                switch ev {
                case .text(let t): text += t; onEvent(.text(t))
                case .toolCall(let c): calls.append(c)
                case .done(let r): raw = r
                }
            }
            finalText += text
            guard !calls.isEmpty, let tools else { return finalText }
            messages.append(AIMessage(role: .assistant, text: text, toolCalls: calls, raw: raw))
            var results: [AIToolResult] = []
            for c in calls {
                onEvent(.status("Đang tra cứu: \(Self.label(c))…"))
                let out = await tools.run(c)
                results.append(AIToolResult(callID: c.id, name: c.name, content: out))
            }
            onEvent(.status(nil))
            messages.append(AIMessage(role: .toolResult, text: "", toolResults: results))
            if round == 5 { onEvent(.text("\n\n_(Đã tra cứu nhiều lượt, dừng tại đây.)_")) }
            if !text.isEmpty { onEvent(.text("\n\n")); finalText += "\n\n" }
        }
        return finalText
    }

    private static func label(_ c: AIToolCall) -> String {
        let a = c.arguments
        func d(_ k: String) -> String {
            guard let s = a[k] as? String, let date = HealthDataTools.date(s) else { return "" }
            let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
            return f.string(from: date)
        }
        switch c.name {
        case "get_day_detail": return "số liệu ngày \(d("date"))"
        case "get_heart_rate_hourly": return "nhịp tim theo giờ \(d("date"))"
        case "get_sleep_nights": return "các đêm \(d("from"))–\(d("to"))"
        case "get_range_table": return "bảng \(d("from"))–\(d("to"))"
        case "get_profile": return "hồ sơ"
        default: return c.name
        }
    }
}

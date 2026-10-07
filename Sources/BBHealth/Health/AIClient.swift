import Foundation

// MARK: - Kiểu dữ liệu chung

/// Một công cụ AI được phép gọi (vd lấy chi tiết 1 ngày). `parametersJSON` = JSON Schema của tham số.
struct AIToolSpec: Sendable {
    let name: String
    let description: String
    let parametersJSON: String

    var parameters: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(parametersJSON.utf8)) as? [String: Any]) ?? ["type": "object"]
    }
}

/// AI yêu cầu chạy một công cụ.
struct AIToolCall: Sendable, Equatable {
    let id: String
    let name: String
    /// Tham số dạng JSON.
    let argumentsJSON: String

    var arguments: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: Any]) ?? [:]
    }
}

struct AIToolResult: Sendable, Equatable {
    let callID: String
    let name: String
    let content: String
}

/// Một lượt hội thoại. `raw` = bản gốc lượt trả lời của hãng (JSON) để gửi lại y nguyên khi tiếp tục
/// (Gemini cần `thoughtSignature`, Claude cần khối thinking) — chỉ dùng trong cùng một hãng.
struct AIMessage: Sendable, Equatable {
    enum Role: String, Sendable { case user, assistant, toolResult }
    var role: Role
    var text: String
    var toolCalls: [AIToolCall] = []
    var toolResults: [AIToolResult] = []
    var raw: String?

    init(role: Role, text: String, toolCalls: [AIToolCall] = [], toolResults: [AIToolResult] = [], raw: String? = nil) {
        self.role = role; self.text = text; self.toolCalls = toolCalls; self.toolResults = toolResults; self.raw = raw
    }
    static func user(_ t: String) -> AIMessage { AIMessage(role: .user, text: t) }
    static func assistant(_ t: String) -> AIMessage { AIMessage(role: .assistant, text: t) }
}

/// Sự kiện chữ chạy dần.
enum AIEvent: Sendable {
    case text(String)
    case toolCall(AIToolCall)
    /// Lượt trả lời kết thúc; `raw` là bản gốc để lưu vào `AIMessage.raw`.
    case done(raw: String?)
}

enum AIError: LocalizedError {
    case http(Int, String)
    case refused
    case empty
    case badURL
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            switch code {
            case 400: return "AI không nhận yêu cầu (400). \(Self.short(body))"
            case 401, 403: return "Khoá không hợp lệ hoặc chưa được phép (\(code)). Vào Cài đặt → Trợ lý AI dán lại khoá."
            case 404: return "Không tìm thấy model hoặc địa chỉ máy chủ (404). Khoá mới tạo của Gemini chỉ dùng được dòng 3.x — chọn Gemini 3.8 Flash hoặc 3.5 Flash-Lite."
            case 429: return "Hết lượt dùng tạm thời (429) — gói miễn phí giới hạn số lượt mỗi phút/ngày. Thử lại sau ít phút hoặc đổi sang model Flash-Lite."
            case 500...599: return "Máy chủ AI đang bận (\(code)). Thử lại sau."
            default: return "Lỗi \(code): \(Self.short(body))"
            }
        case .refused: return "AI từ chối trả lời yêu cầu này."
        case .empty: return "AI không trả về nội dung. Thử lại."
        case .badURL: return "Địa chỉ máy chủ không hợp lệ."
        case .unavailable(let why): return why
        }
    }
    private static func short(_ s: String) -> String { String(s.prefix(220)) }
}

/// Nhà cung cấp AI: gửi `system` + hội thoại (+ công cụ), nhận sự kiện chạy dần.
/// Mỗi hãng một bản cài — thêm hãng mới chỉ cần thêm một struct.
protocol AIClient: Sendable {
    var displayName: String { get }
    var model: String { get }
    /// Có hỗ trợ gọi công cụ không (AI trên máy thì không).
    var supportsTools: Bool { get }
    /// Cần gói dữ liệu rút gọn (cửa sổ ngữ cảnh nhỏ — AI trên máy).
    var prefersCompactContext: Bool { get }
    func stream(system: String, messages: [AIMessage], tools: [AIToolSpec], maxTokens: Int) -> AsyncThrowingStream<AIEvent, Error>
}

extension AIClient {
    var supportsTools: Bool { true }
    var prefersCompactContext: Bool { false }

    /// Chỉ lấy chữ (không công cụ).
    func textStream(system: String, messages: [AIMessage], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    for try await ev in stream(system: system, messages: messages, tools: [], maxTokens: maxTokens) {
                        if case .text(let t) = ev { c.yield(t) }
                    }
                    c.finish()
                } catch { c.finish(throwing: error) }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    /// Gom hết luồng thành một chuỗi (dùng cho "Kiểm tra kết nối").
    func complete(system: String, messages: [AIMessage], maxTokens: Int = 256) async throws -> String {
        var out = ""
        for try await chunk in textStream(system: system, messages: messages, maxTokens: maxTokens) { out += chunk }
        return out
    }
}

// MARK: - Đọc Server-Sent Events

enum SSE {
    /// Gửi request, đọc từng dòng `data: …` và đưa JSON cho `handle` (trả về các sự kiện). Khi hết luồng gọi
    /// `finish` để lấy bản gốc lượt trả lời. `handle` ném lỗi để dừng (vd refusal).
    static func run(_ request: URLRequest,
                    handle: @escaping @Sendable ([String: Any]) throws -> [AIEvent],
                    finish: @escaping @Sendable () -> String?) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    guard (200..<300).contains(status) else {
                        var body = ""
                        for try await line in bytes.lines { body += line; if body.count > 2000 { break } }
                        throw AIError.http(status, body)
                    }
                    var produced = false
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        for ev in try handle(json) {
                            if case .text(let t) = ev, t.isEmpty { continue }
                            produced = true
                            continuation.yield(ev)
                        }
                    }
                    if !produced { throw AIError.empty }
                    continuation.yield(.done(raw: finish()))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func jsonRequest(url: URL, headers: [String: String], body: [String: Any]) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 180
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    static func jsonString(_ obj: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(obj), let d = try? JSONSerialization.data(withJSONObject: obj) else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func jsonObject(_ s: String?) -> Any? {
        guard let s, let d = s.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
}

/// Gom các mảnh trả lời của một lượt (dùng chung cho 3 hãng) — chạy trong closure @Sendable nên khoá.
final class TurnAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""
    /// Các khối gốc theo thứ tự (hãng tự định nghĩa).
    private var blocks: [Any] = []
    private var pending: [Int: (id: String, name: String, args: String, extra: [String: Any])] = [:]

    func appendText(_ t: String) { lock.withLock { text += t } }
    func startTool(index: Int, id: String, name: String, extra: [String: Any] = [:]) {
        lock.withLock { pending[index] = (id, name, "", extra) }
    }
    func appendToolArgs(index: Int, _ s: String) { lock.withLock { pending[index]?.args += s } }
    func setToolArgs(index: Int, _ s: String) { lock.withLock { pending[index]?.args = s } }
    func finishTool(index: Int) -> AIToolCall? {
        lock.withLock {
            guard let p = pending.removeValue(forKey: index) else { return nil }
            let args = p.args.isEmpty ? "{}" : p.args
            blocks.append(["__tool": true, "id": p.id, "name": p.name, "args": args, "extra": p.extra])
            return AIToolCall(id: p.id, name: p.name, argumentsJSON: args)
        }
    }
    func finishAllTools() -> [AIToolCall] { lock.withLock { pending.keys.sorted() }.compactMap { finishTool(index: $0) } }
    func addBlock(_ b: Any) { lock.withLock { blocks.append(b) } }
    var allText: String { lock.withLock { text } }
    var allBlocks: [Any] { lock.withLock { blocks } }
}

// MARK: - Google Gemini (generativelanguage v1beta, streamGenerateContent?alt=sse)

struct GeminiClient: AIClient {
    let apiKey: String
    let model: String
    var displayName: String { "Gemini" }

    func stream(system: String, messages: [AIMessage], tools: [AIToolSpec], maxTokens: Int) -> AsyncThrowingStream<AIEvent, Error> {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse") else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.badURL) }
        }
        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": messages.map(Self.content),
            // Gemini tính cả token "suy nghĩ" vào giới hạn → để rộng.
            "generationConfig": ["maxOutputTokens": max(maxTokens, 8192)],
        ]
        if !tools.isEmpty {
            body["tools"] = [["functionDeclarations": tools.map {
                ["name": $0.name, "description": $0.description, "parameters": $0.parameters] }]]
        }
        let req = SSE.jsonRequest(url: url, headers: ["x-goog-api-key": apiKey], body: body)
        let acc = TurnAccumulator()
        var toolIndex = 0
        return SSE.run(req, handle: { json in
            guard let c = (json["candidates"] as? [[String: Any]])?.first else {
                if let fb = json["promptFeedback"] as? [String: Any], fb["blockReason"] != nil { throw AIError.refused }
                return []
            }
            var out: [AIEvent] = []
            let parts = (c["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
            for p in parts {
                if (p["thought"] as? Bool) == true { continue }
                if let t = p["text"] as? String {
                    acc.appendText(t); acc.addBlock(p); out.append(.text(t))
                } else if let fc = p["functionCall"] as? [String: Any], let name = fc["name"] as? String {
                    let args = SSE.jsonString(fc["args"] ?? [:]) ?? "{}"
                    let id = (fc["id"] as? String) ?? "call_\(toolIndex)"
                    // Gemini 3 bắt gửi lại `thoughtSignature` kèm functionCall → giữ nguyên part gốc.
                    acc.addBlock(p)
                    toolIndex += 1
                    out.append(.toolCall(AIToolCall(id: id, name: name, argumentsJSON: args)))
                }
            }
            return out
        }, finish: {
            SSE.jsonString(["role": "model", "parts": acc.allBlocks])
        })
    }

    /// Đổi `AIMessage` → `content` của Gemini.
    private static func content(_ m: AIMessage) -> [String: Any] {
        switch m.role {
        case .user:
            return ["role": "user", "parts": [["text": m.text]]]
        case .assistant:
            if let raw = SSE.jsonObject(m.raw) as? [String: Any] { return raw }
            var parts: [[String: Any]] = m.text.isEmpty ? [] : [["text": m.text]]
            for c in m.toolCalls { parts.append(["functionCall": ["name": c.name, "args": c.arguments]]) }
            return ["role": "model", "parts": parts]
        case .toolResult:
            return ["role": "user", "parts": m.toolResults.map {
                ["functionResponse": ["name": $0.name, "response": ["result": $0.content]]] }]
        }
    }
}

// MARK: - Claude (Anthropic Messages API, stream: true)

struct ClaudeClient: AIClient {
    let apiKey: String
    let model: String
    var displayName: String { "Claude" }

    func stream(system: String, messages: [AIMessage], tools: [AIToolSpec], maxTokens: Int) -> AsyncThrowingStream<AIEvent, Error> {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.badURL) }
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": max(maxTokens, 4096),
            "system": system,
            "messages": messages.map(Self.message),
            "stream": true,
        ]
        if !tools.isEmpty {
            body["tools"] = tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters] }
        }
        var headers = ["x-api-key": apiKey, "anthropic-version": "2023-06-01"]
        // Opus 5.5 / Sonnet 5.5: đặt rõ mức effort (mặc định Opus 5.5 là medium) + fallback khi bị từ chối
        // nhầm. Haiku 4.5 không nhận `effort` → bỏ qua.
        if model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-sonnet-5") {
            body["output_config"] = ["effort": "medium"]
            body["fallbacks"] = "default"
            headers["anthropic-beta"] = "server-side-fallback-2026-07-01"
        }
        let req = SSE.jsonRequest(url: url, headers: headers, body: body)
        let acc = TurnAccumulator()
        // Khối đang mở theo index: text / tool_use / thinking (giữ nguyên để gửi lại).
        let open = OpenBlocks()
        return SSE.run(req, handle: { json in
            switch json["type"] as? String {
            case "content_block_start":
                let idx = json["index"] as? Int ?? 0
                let block = json["content_block"] as? [String: Any] ?? [:]
                switch block["type"] as? String {
                case "tool_use":
                    acc.startTool(index: idx, id: block["id"] as? String ?? "toolu_\(idx)", name: block["name"] as? String ?? "")
                    open.set(idx, kind: "tool_use")
                case "text":
                    open.set(idx, kind: "text")
                default:
                    // thinking / redacted_thinking: giữ nguyên khối, gom delta.
                    open.set(idx, kind: block["type"] as? String ?? "other", block: block)
                }
                return []
            case "content_block_delta":
                let idx = json["index"] as? Int ?? 0
                let delta = json["delta"] as? [String: Any] ?? [:]
                switch delta["type"] as? String {
                case "text_delta":
                    let t = delta["text"] as? String ?? ""
                    acc.appendText(t); open.appendText(idx, t)
                    return [.text(t)]
                case "input_json_delta":
                    acc.appendToolArgs(index: idx, delta["partial_json"] as? String ?? "")
                case "thinking_delta":
                    open.appendField(idx, "thinking", delta["thinking"] as? String ?? "")
                case "signature_delta":
                    open.appendField(idx, "signature", delta["signature"] as? String ?? "")
                default: break
                }
                return []
            case "content_block_stop":
                let idx = json["index"] as? Int ?? 0
                guard let b = open.take(idx) else { return [] }
                switch b.kind {
                case "tool_use":
                    if let call = acc.finishTool(index: idx) {
                        acc.addBlock(["type": "tool_use", "id": call.id, "name": call.name, "input": call.arguments])
                        return [.toolCall(call)]
                    }
                case "text":
                    if !b.text.isEmpty { acc.addBlock(["type": "text", "text": b.text]) }
                default:
                    acc.addBlock(b.block)
                }
                return []
            case "message_delta":
                if (json["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" { throw AIError.refused }
                return []
            case "error":
                let msg = ((json["error"] as? [String: Any])?["message"] as? String) ?? "lỗi máy chủ"
                throw AIError.http(529, msg)
            default:
                return []
            }
        }, finish: {
            SSE.jsonString(["role": "assistant", "content": acc.allBlocks])
        })
    }

    private static func message(_ m: AIMessage) -> [String: Any] {
        switch m.role {
        case .user:
            return ["role": "user", "content": m.text]
        case .assistant:
            if let raw = SSE.jsonObject(m.raw) as? [String: Any] { return raw }
            var content: [[String: Any]] = m.text.isEmpty ? [] : [["type": "text", "text": m.text]]
            for c in m.toolCalls { content.append(["type": "tool_use", "id": c.id, "name": c.name, "input": c.arguments]) }
            return ["role": "assistant", "content": content]
        case .toolResult:
            return ["role": "user", "content": m.toolResults.map {
                ["type": "tool_result", "tool_use_id": $0.callID, "content": $0.content] }]
        }
    }

    /// Theo dõi các khối đang mở của Claude (để gửi lại nguyên khối thinking).
    final class OpenBlocks: @unchecked Sendable {
        struct Block { var kind: String; var text = ""; var block: [String: Any] }
        private let lock = NSLock()
        private var map: [Int: Block] = [:]
        func set(_ i: Int, kind: String, block: [String: Any] = [:]) { lock.withLock { map[i] = Block(kind: kind, block: block) } }
        func appendText(_ i: Int, _ t: String) { lock.withLock { map[i]?.text += t } }
        func appendField(_ i: Int, _ key: String, _ v: String) {
            lock.withLock {
                guard var b = map[i] else { return }
                b.block[key] = ((b.block[key] as? String) ?? "") + v
                map[i] = b
            }
        }
        func take(_ i: Int) -> Block? { lock.withLock { map.removeValue(forKey: i) } }
    }
}

// MARK: - OpenAI / máy chủ tương thích (chat/completions, stream: true)

struct OpenAICompatibleClient: AIClient {
    let apiKey: String
    let model: String
    let baseURL: String
    var displayName: String { "AI" }

    func stream(system: String, messages: [AIMessage], tools: [AIToolSpec], maxTokens: Int) -> AsyncThrowingStream<AIEvent, Error> {
        let base = baseURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/chat/completions") else {
            return AsyncThrowingStream { $0.finish(throwing: AIError.badURL) }
        }
        let msgs: [[String: Any]] = [["role": "system", "content": system]] + messages.flatMap(Self.messages)
        var body: [String: Any] = ["model": model, "messages": msgs, "stream": true]
        if !tools.isEmpty {
            body["tools"] = tools.map { ["type": "function", "function": ["name": $0.name, "description": $0.description, "parameters": $0.parameters]] }
        }
        var headers: [String: String] = [:]
        if !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        let req = SSE.jsonRequest(url: url, headers: headers, body: body)
        let acc = TurnAccumulator()
        return SSE.run(req, handle: { json in
            guard let choice = (json["choices"] as? [[String: Any]])?.first else { return [] }
            let delta = choice["delta"] as? [String: Any] ?? [:]
            var out: [AIEvent] = []
            if let t = delta["content"] as? String, !t.isEmpty { acc.appendText(t); out.append(.text(t)) }
            for tc in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let idx = tc["index"] as? Int ?? 0
                let fn = tc["function"] as? [String: Any] ?? [:]
                if let id = tc["id"] as? String { acc.startTool(index: idx, id: id, name: fn["name"] as? String ?? "") }
                if let a = fn["arguments"] as? String { acc.appendToolArgs(index: idx, a) }
            }
            if let reason = choice["finish_reason"] as? String {
                if reason == "content_filter" { throw AIError.refused }
                for call in acc.finishAllTools() { out.append(.toolCall(call)) }
            }
            return out
        }, finish: {
            let calls = acc.allBlocks.compactMap { $0 as? [String: Any] }.filter { $0["__tool"] as? Bool == true }
            var m: [String: Any] = ["role": "assistant", "content": acc.allText]
            if !calls.isEmpty {
                m["tool_calls"] = calls.map { ["id": $0["id"] ?? "", "type": "function",
                                               "function": ["name": $0["name"] ?? "", "arguments": $0["args"] ?? "{}"]] }
            }
            return SSE.jsonString(m)
        })
    }

    private static func messages(_ m: AIMessage) -> [[String: Any]] {
        switch m.role {
        case .user: return [["role": "user", "content": m.text]]
        case .assistant:
            if let raw = SSE.jsonObject(m.raw) as? [String: Any] { return [raw] }
            var d: [String: Any] = ["role": "assistant", "content": m.text]
            if !m.toolCalls.isEmpty {
                d["tool_calls"] = m.toolCalls.map { ["id": $0.id, "type": "function", "function": ["name": $0.name, "arguments": $0.argumentsJSON]] }
            }
            return [d]
        case .toolResult:
            return m.toolResults.map { ["role": "tool", "tool_call_id": $0.callID, "content": $0.content] }
        }
    }
}

// MARK: - Tự chuyển model dự phòng

/// Thử lần lượt từng client; client trước lỗi 404 (model không mở cho khoá này), 429 (hết lượt) hoặc
/// 5xx (quá tải) **trước khi kịp trả chữ** thì chuyển sang client sau. `model` = model thực sự đã trả lời.
final class FallbackAIClient: AIClient, @unchecked Sendable {
    let clients: [any AIClient]
    private let lock = NSLock()
    private var used: String?

    init(clients: [any AIClient]) { self.clients = clients }

    var displayName: String { clients.first?.displayName ?? "AI" }
    var model: String { lock.withLock { used } ?? clients.first?.model ?? "" }

    func stream(system: String, messages: [AIMessage], tools: [AIToolSpec], maxTokens: Int) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                var lastError: Error = AIError.empty
                for client in clients {
                    var produced = false
                    do {
                        for try await ev in client.stream(system: system, messages: messages, tools: tools, maxTokens: maxTokens) {
                            if !produced { produced = true; lock.withLock { used = client.model } }
                            c.yield(ev)
                        }
                        c.finish(); return
                    } catch {
                        lastError = error
                        guard !produced, case AIError.http(let code, _) = error,
                              code == 404 || code == 429 || code >= 500 else { break }
                    }
                }
                c.finish(throwing: lastError)
            }
            c.onTermination = { _ in task.cancel() }
        }
    }
}

// MARK: - Giả lập (simulator, chưa có khoá) — để xem giao diện

struct MockAIClient: AIClient {
    var displayName: String { "AI giả lập" }
    var model: String { "mock" }

    func stream(system: String, messages: [AIMessage], tools: [AIToolSpec], maxTokens: Int) -> AsyncThrowingStream<AIEvent, Error> {
        let lastUser = messages.last { $0.role == .user }?.text ?? ""
        let isChat = messages.count > 1 || lastUser.count < 400
        let text: String
        if isChat {
            text = """
            **Trả lời (giả lập)**
            Em đã xem lại 7 đêm gần nhất: anh dậy sớm 4/7 đêm, đều rơi vào hôm ăn tối sau 20h hoặc có rượu bia. \
            Đêm ngủ tốt nhất là tối thứ Ba — lên giường 22h40, không bữa muộn, ngủ 7,2 giờ.
            - Thử xong bữa tối trước 19h30 trong 3 ngày tới.
            - Nếu vẫn dậy sớm, lùi giờ lên giường 30 phút.

            _(Nội dung giả lập trên máy ảo.)_
            """
        } else {
            text = """
            **1. Tình trạng chung**
            Tuần này anh giữ được nhịp sinh hoạt khá ổn, nhưng **giấc ngủ vẫn thiếu** (trung bình 6,3 giờ) và có **2 buổi rượu bia** kéo nhịp tim nghỉ lên.

            **2. Giấc ngủ**
            - Chỉ khoảng nửa số đêm đạt 7 giờ.
            - Đêm sau hôm uống rượu ngủ ít hơn rõ rệt.

            **3. Ba việc nên làm tuần tới**
            - Lên giường trước 23h, tắt màn hình từ 22h.
            - Nếu phải tiếp khách: ăn no trước, tối đa 1–2 ly, không uống sau 21h.
            - Giữ đủ 6 bữa nhỏ, thêm bữa phụ chiều có sữa.

            _(Đây là nội dung giả lập trên máy ảo.)_
            """
        }
        return AsyncThrowingStream { c in
            let task = Task {
                for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                    try? await Task.sleep(for: .milliseconds(18))
                    c.yield(.text(String(word) + " "))
                }
                c.yield(.done(raw: nil))
                c.finish()
            }
            c.onTermination = { _ in task.cancel() }
        }
    }
}

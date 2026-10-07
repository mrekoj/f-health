import Foundation
import Observation

/// Hãng AI người dùng chọn trong Cài đặt → Trợ lý AI (T-026). Mỗi người tự dán khoá của mình (BYOK):
/// app không có máy chủ, không nhúng khoá của chủ app.
enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    /// Chỉ báo cáo tự tính + sao chép (mức 0).
    case none
    /// Apple Intelligence chạy trong máy (iOS 26) — không khoá, không gửi dữ liệu đi (T-028).
    case appleOnDevice
    case gemini
    case claude
    /// Máy chủ kiểu OpenAI: OpenAI, OpenRouter, Ollama/LM Studio trong nhà…
    case openAICompatible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Không dùng AI"
        case .appleOnDevice: return "AI trên iPhone (Apple)"
        case .gemini: return "Google Gemini"
        case .claude: return "Claude (Anthropic)"
        case .openAICompatible: return "OpenAI / máy chủ tương thích"
        }
    }

    var subtitle: String {
        switch self {
        case .none: return "Chỉ báo cáo tự tính theo ngưỡng + sao chép dán sang ứng dụng AI khác."
        case .appleOnDevice: return "Không cần tài khoản, dữ liệu không rời máy. Cần iOS 26 + Apple Intelligence. Trả lời ngắn gọn hơn, không tự tra cứu thêm."
        case .gemini: return "Có gói miễn phí — chỉ cần tài khoản Google, lấy khoá ~2 phút."
        case .claude: return "Trả theo lượt dùng (~1–3 xu mỗi báo cáo). Cần khoá từ console.anthropic.com."
        case .openAICompatible: return "ChatGPT (khoá OpenAI), OpenRouter, hoặc Ollama chạy trong nhà."
        }
    }

    var symbol: String {
        switch self {
        case .none: return "doc.on.doc"
        case .appleOnDevice: return "iphone.gen3"
        case .gemini: return "sparkle"
        case .claude: return "asterisk"
        case .openAICompatible: return "server.rack"
        }
    }

    /// Các model gợi ý (model đầu là mặc định). Người dùng gõ tên khác được.
    var suggestedModels: [(id: String, label: String)] {
        switch self {
        case .none, .appleOnDevice: return []
        // Google chỉ cho dự án mới dùng dòng 3.x (2.5 bị giới hạn cho người đã dùng trước) — PO gặp 404 05/10.
        case .gemini: return [("gemini-3.8-flash", "Gemini 3.8 Flash — miễn phí, khuyên dùng"),
                              ("gemini-3.5-flash-lite", "Gemini 3.5 Flash-Lite — nhanh, nhiều lượt hơn"),
                              ("gemini-3.1-flash-lite", "Gemini 3.1 Flash-Lite"),
                              ("gemini-2.5-flash", "Gemini 2.5 Flash — chỉ khoá cũ")]
        case .claude: return [("claude-opus-5-5", "Claude Opus 5.5 — tốt nhất"),
                              ("claude-sonnet-5-5", "Claude Sonnet 5.5 — rẻ hơn"),
                              ("claude-haiku-4-5", "Claude Haiku 4.5 — rẻ nhất")]
        case .openAICompatible: return [("gpt-5-mini", "OpenAI GPT-5 mini"),
                                        ("llama3.1", "Ollama llama3.1 (máy trong nhà)")]
        }
    }

    var defaultModel: String { suggestedModels.first?.id ?? "" }
    /// Model mạnh cho "Phân tích sâu" (T-031).
    var deepModel: String {
        switch self {
        case .gemini: return "gemini-3.8-flash"
        case .claude: return "claude-opus-5-5"
        case .openAICompatible, .none, .appleOnDevice: return defaultModel
        }
    }

    /// Trang lấy khoá.
    var keyURL: URL? {
        switch self {
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")
        case .claude: return URL(string: "https://console.anthropic.com/settings/keys")
        case .openAICompatible: return URL(string: "https://platform.openai.com/api-keys")
        case .none, .appleOnDevice: return nil
        }
    }

    /// Dòng quyền riêng tư hiện trước khi gửi lần đầu.
    var privacyNote: String {
        switch self {
        case .none: return ""
        case .appleOnDevice: return "Mô hình chạy ngay trong iPhone: hồ sơ và số liệu không gửi đi đâu."
        case .gemini: return "Báo cáo (hồ sơ + số liệu) sẽ gửi tới Google Gemini bằng khoá của bạn. Với gói MIỄN PHÍ, Google có thể dùng nội dung để cải thiện sản phẩm và người của Google có thể đọc — đừng ghi tên thật/thông tin định danh vào hồ sơ nếu ngại. Gói trả phí thì Google không dùng."
        case .claude: return "Báo cáo (hồ sơ + số liệu) sẽ gửi tới Anthropic (Claude) bằng khoá của bạn. Anthropic không dùng dữ liệu gửi qua khoá API để huấn luyện mô hình."
        case .openAICompatible: return "Báo cáo (hồ sơ + số liệu) sẽ gửi tới máy chủ anh nhập. Với OpenAI, dữ liệu qua khoá API mặc định không dùng để huấn luyện; với Ollama trong nhà, dữ liệu không ra Internet."
        }
    }

    var needsKey: Bool { self != .none && self != .appleOnDevice }
}

/// Cấu hình Trợ lý AI. Khoá API lưu **Keychain**; phần còn lại UserDefaults.
@Observable
@MainActor
final class AISettings {
    static let shared = AISettings()

    private enum Keys {
        static let kind = "bbh.ai.kind"
        static func model(_ k: AIProviderKind) -> String { "bbh.ai.model.\(k.rawValue)" }
        static let baseURL = "bbh.ai.baseURL"
        static let morningTip = "bbh.ai.morningTip"
        static func consent(_ k: AIProviderKind) -> String { "bbh.ai.consent.\(k.rawValue)" }
        static func keychain(_ k: AIProviderKind) -> String { "ai.key.\(k.rawValue)" }
    }
    private let defaults = UserDefaults.standard

    var kind: AIProviderKind { didSet { defaults.set(kind.rawValue, forKey: Keys.kind) } }
    /// Base URL cho máy chủ tương thích OpenAI (mặc định OpenAI).
    var baseURL: String { didSet { defaults.set(baseURL, forKey: Keys.baseURL) } }
    /// Thẻ "Lời khuyên sáng nay" ở Hôm nay (T-032) — mặc định bật.
    var morningTip: Bool { didSet { defaults.set(morningTip, forKey: Keys.morningTip) } }
    /// Tăng mỗi lần đổi khoá để view cập nhật trạng thái "đã có khoá".
    private(set) var keyRevision = 0

    init() {
        kind = AIProviderKind(rawValue: defaults.string(forKey: Keys.kind) ?? "") ?? .none
        baseURL = defaults.string(forKey: Keys.baseURL) ?? "https://api.openai.com/v1"
        morningTip = defaults.object(forKey: Keys.morningTip) as? Bool ?? true
        #if DEBUG
        // Chụp màn/kiểm sim: `SIMCTL_CHILD_BBH_AI_KIND=gemini SIMCTL_CHILD_BBH_AI_KEY=…` (không ghi vào máy).
        let env = ProcessInfo.processInfo.environment
        if let k = env["BBH_AI_KIND"].flatMap(AIProviderKind.init(rawValue:)) { kind = k }
        #endif
    }

    func model(for k: AIProviderKind) -> String {
        let m = defaults.string(forKey: Keys.model(k))?.trimmingCharacters(in: .whitespaces) ?? ""
        return m.isEmpty ? k.defaultModel : m
    }
    func setModel(_ m: String, for k: AIProviderKind) {
        defaults.set(m.trimmingCharacters(in: .whitespaces), forKey: Keys.model(k))
        keyRevision += 1
    }

    func apiKey(for k: AIProviderKind) -> String? {
        #if DEBUG
        if k == kind, let env = ProcessInfo.processInfo.environment["BBH_AI_KEY"], !env.isEmpty { return env }
        #endif
        return Keychain.get(Keys.keychain(k))
    }
    func setAPIKey(_ key: String?, for k: AIProviderKind) {
        let t = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set((t?.isEmpty ?? true) ? nil : t, for: Keys.keychain(k))
        keyRevision += 1
    }

    func hasConsented(_ k: AIProviderKind) -> Bool { defaults.bool(forKey: Keys.consent(k)) }
    func setConsented(_ k: AIProviderKind) { defaults.set(true, forKey: Keys.consent(k)) }

    /// Đã đủ điều kiện gọi AI chưa (có hãng + khoá; Ollama trong nhà có thể không cần khoá).
    var isReady: Bool {
        _ = keyRevision
        switch kind {
        case .none: return false
        case .appleOnDevice: return OnDeviceAI.status.isAvailable
        case .openAICompatible:
            return apiKey(for: kind) != nil || !baseURL.contains("api.openai.com")
        default: return apiKey(for: kind) != nil
        }
    }

    /// Mô tả ngắn: "Google Gemini · gemini-2.5-flash".
    var summary: String {
        _ = keyRevision
        guard kind != .none else { return "Chỉ báo cáo + sao chép" }
        if kind == .appleOnDevice { return kind.title }
        return "\(kind.title) · \(model(for: kind))"
    }

    /// Tạo client theo cấu hình hiện tại (nil nếu chưa đủ điều kiện). `deep` = model mạnh (Phân tích sâu).
    func makeClient(deep: Bool = false) -> (any AIClient)? {
        guard isReady else { return nil }
        let key = apiKey(for: kind) ?? ""
        let model = deep ? kind.deepModel : model(for: kind)
        switch kind {
        case .none: return nil
        case .appleOnDevice: return OnDeviceAI.makeClient()
        case .gemini:
            // Model chọn trước, rồi các model gợi ý còn lại làm dự phòng (404/quá tải/hết lượt).
            let chain = [model] + AIProviderKind.gemini.suggestedModels.map(\.id).filter { $0 != model }
            return FallbackAIClient(clients: chain.map { GeminiClient(apiKey: key, model: $0) })
        case .claude: return ClaudeClient(apiKey: key, model: model)
        case .openAICompatible: return OpenAICompatibleClient(apiKey: key, model: model, baseURL: baseURL)
        }
    }
}

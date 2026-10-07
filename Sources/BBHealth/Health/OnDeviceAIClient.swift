import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// **AI trên iPhone** (T-028): mô hình Apple Intelligence chạy ngay trong máy (`FoundationModels`, iOS 26).
/// Không tài khoản, không khoá, dữ liệu không rời máy. Cửa sổ ngữ cảnh nhỏ (~4.000 token) → người gọi
/// phải dùng gói rút gọn (`prefersCompactContext`). Không hỗ trợ công cụ.
enum OnDeviceAI {
    enum Status: Equatable {
        case available
        case unavailable(String)
        case unsupported

        var isAvailable: Bool { self == .available }
        var text: String {
            switch self {
            case .available: return "Sẵn sàng trên máy này"
            case .unavailable(let why): return why
            case .unsupported: return "Cần iPhone 15 Pro trở lên / iPhone 16, 17 và iOS 26"
            }
        }
    }

    /// Máy này có dùng được không (iOS 26 + Apple Intelligence đã bật + model đã tải).
    static var status: Status {
        #if canImport(FoundationModels)
        if #available(iOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible: return .unavailable("Máy này không hỗ trợ Apple Intelligence")
                case .appleIntelligenceNotEnabled: return .unavailable("Chưa bật Apple Intelligence (Cài đặt máy → Apple Intelligence & Siri)")
                case .modelNotReady: return .unavailable("Mô hình đang tải về máy — thử lại sau ít phút")
                @unknown default: return .unavailable("Chưa dùng được trên máy này")
                }
            }
        }
        #endif
        return .unsupported
    }

    static func makeClient() -> (any AIClient)? {
        #if canImport(FoundationModels)
        if #available(iOS 26, *), status.isAvailable { return OnDeviceAIClient() }
        #endif
        return nil
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
struct OnDeviceAIClient: AIClient {
    var displayName: String { "AI trên iPhone" }
    var model: String { "apple-on-device" }
    var supportsTools: Bool { false }
    var prefersCompactContext: Bool { true }

    func stream(system: String, messages: [AIMessage], tools: [AIToolSpec], maxTokens: Int) -> AsyncThrowingStream<AIEvent, Error> {
        AsyncThrowingStream { c in
            let task = Task {
                do {
                    // Hội thoại trước đó ghép vào lời dặn (mô hình trên máy không có API lịch sử nhiều lượt theo vai).
                    let history = messages.dropLast().filter { $0.role != .toolResult }
                        .map { ($0.role == .user ? "Người dùng: " : "Trợ lý: ") + $0.text }.joined(separator: "\n")
                    let instructions = system + (history.isEmpty ? "" : "\n\nHội thoại trước:\n" + String(history.suffix(1500)))
                    let prompt = messages.last?.text ?? ""
                    let session = LanguageModelSession(instructions: instructions)
                    var sent = ""
                    for try await partial in session.streamResponse(to: prompt) {
                        try Task.checkCancellation()
                        let whole = partial.content
                        guard whole.count > sent.count else { continue }
                        let delta = String(whole.dropFirst(sent.count))
                        sent = whole
                        if !delta.isEmpty { c.yield(.text(delta)) }
                    }
                    if sent.isEmpty { throw AIError.empty }
                    c.yield(.done(raw: nil))
                    c.finish()
                } catch let e as LanguageModelSession.GenerationError {
                    c.finish(throwing: AIError.unavailable(Self.describe(e)))
                } catch {
                    c.finish(throwing: error)
                }
            }
            c.onTermination = { _ in task.cancel() }
        }
    }

    private static func describe(_ e: LanguageModelSession.GenerationError) -> String {
        switch e {
        case .exceededContextWindowSize: return "Nội dung quá dài cho mô hình trên máy — thử kỳ ngắn hơn (Ngày/Tuần) hoặc đổi sang Gemini/Claude."
        case .guardrailViolation: return "Mô hình trên máy từ chối nội dung này (bộ lọc an toàn của Apple). Thử hỏi cách khác hoặc đổi sang Gemini/Claude."
        case .unsupportedLanguageOrLocale: return "Mô hình trên máy chưa hỗ trợ ngôn ngữ này."
        case .assetsUnavailable: return "Mô hình trên máy chưa tải xong — thử lại sau."
        case .rateLimited: return "Mô hình trên máy đang bận — thử lại sau ít phút."
        default: return "Mô hình trên máy gặp lỗi: \(e.localizedDescription)"
        }
    }
}
#endif

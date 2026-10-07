import SwiftUI
import SwiftData

/// Màn **Hỏi đáp với AI** (T-027): hội thoại chạy dần, AI tự gọi công cụ lấy thêm số liệu, gợi ý câu hỏi,
/// lưu lịch sử theo kỳ. Mở từ màn Báo cáo (kỳ đang xem) hoặc Giấc ngủ/Nhịp tim (ngày đang xem).
struct AIChatView: View {
    let report: HealthReport
    /// Câu hỏi đầu gửi sẵn (vd từ nút "Hỏi AI" ở Giấc ngủ chi tiết).
    var initialQuestion: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var ai = AISettings.shared
    @State private var settings = AppSettings.shared
    @State private var messages: [ChatItem] = []
    @State private var draft = ""
    @State private var streaming = ""
    @State private var status: String?
    @State private var running = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var showingAISettings = false
    @FocusState private var focused: Bool

    struct ChatItem: Identifiable, Equatable {
        let id: UUID
        let role: AIMessage.Role
        var text: String
    }

    private var contextKey: String { "\(report.period.kind.rawValue)|\(HealthDataTools.ymd(report.period.end))" }

    private var client: (any AIClient)? {
        if let c = ai.makeClient() { return c }
        return HealthStoreFactory.useMock && ai.kind != .none ? MockAIClient() : nil
    }

    private var suggestions: [String] {
        var s = ["Tuần này tôi ngủ kém nhất đêm nào, vì sao?",
                 "Giờ đi ngủ và giờ dậy của tôi có đều không?",
                 "Rượu bia ảnh hưởng gì đến nhịp tim và giấc ngủ của tôi?",
                 "3 việc cụ thể tôi nên làm từ ngày mai?"]
        if report.period.kind == .day {
            s = ["Đêm qua tôi ngủ thế nào, thức lúc mấy giờ?",
                 "Nhịp tim hôm nay có gì bất thường không?",
                 "Hôm nay tôi nên ăn ngủ thế nào?",
                 "So với 7 ngày trước thì sao?"]
        }
        if report.days.contains(where: \.earlyWake) { s.insert("Vì sao tôi hay dậy sớm trước 5h30?", at: 0) }
        return Array(s.prefix(4))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            header
                            ForEach(messages) { bubble($0) }
                            if running || !streaming.isEmpty {
                                assistantBubble(streaming, live: true).id("live")
                            }
                            if let e = error {
                                Label(e, systemImage: "exclamationmark.triangle.fill")
                                    .font(.callout).foregroundStyle(Theme.improve)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if messages.isEmpty && !running { suggestionChips }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, Theme.Space.page)
                        .padding(.vertical, Theme.Space.m)
                    }
                    .onChange(of: streaming) { proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: messages.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .scrollDismissesKeyboard(.interactively)
                }
                inputBar
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Hỏi AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button { showingAISettings = true } label: { Label("Thiết lập AI", systemImage: "gearshape") }
                        Button(role: .destructive) { clear() } label: { Label("Xoá hội thoại", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } }
            }
            .sheet(isPresented: $showingAISettings) { AISettingsView() }
            .task {
                messages = AIChatMessage.history(for: contextKey, in: modelContext).map {
                    ChatItem(id: $0.id, role: $0.role == "user" ? .user : .assistant, text: $0.text) }
                if let q = initialQuestion, messages.isEmpty { send(q) }
                else if DebugOptions.chatQuestion != nil, messages.isEmpty, let q = DebugOptions.chatQuestion { send(q) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: "sparkles", tint: Theme.brand, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hỏi về \(report.period.title.lowercased())").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                Text(client == nil ? "Chưa thiết lập AI — chạm ⋯ để chọn Gemini/Claude" : "AI có số liệu kỳ này và tự tra cứu thêm ngày khác khi cần. Chỉ để tham khảo, không thay bác sĩ.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).card(tint: Theme.brand, radius: Theme.Radius.small)
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gợi ý câu hỏi").font(.label).foregroundStyle(Theme.textSecondary)
            ForEach(suggestions, id: \.self) { q in
                Button { send(q) } label: {
                    HStack {
                        Text(q).font(.callout).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(Theme.brand)
                    }
                    .padding(12).card(radius: Theme.Radius.small)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func bubble(_ m: ChatItem) -> some View {
        if m.role == .user {
            HStack {
                Spacer(minLength: 40)
                Text(m.text).font(.body).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            assistantBubble(m.text, live: false)
        }
    }

    private func assistantBubble(_ text: String, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if text.isEmpty && live {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status ?? "Đang suy nghĩ…").font(.callout).foregroundStyle(Theme.textSecondary) }
            } else {
                AIMarkdownText(text: text)
                if live, let status { Label(status, systemImage: "magnifyingglass").font(.footnote).foregroundStyle(Theme.textTertiary) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: Theme.Radius.small)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Hỏi về giấc ngủ, nhịp tim, ăn uống…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.hairline))
            if running {
                Button { task?.cancel() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 34)).foregroundStyle(Theme.improve)
                }
            } else {
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                        .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.textTertiary : Theme.brand)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(.horizontal, Theme.Space.page).padding(.vertical, 10)
        .background(Theme.background)
    }

    // MARK: - Gửi

    private func send(_ q: String) {
        let question = q.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !running else { return }
        guard let client else { showingAISettings = true; return }
        draft = ""; error = nil; streaming = ""; status = nil
        let userItem = ChatItem(id: UUID(), role: .user, text: question)
        messages.append(userItem)
        persist(userItem)
        running = true
        let history = messages.map { AIMessage(role: $0.role, text: $0.text) }
        let tools = HealthDataTools(provider: HealthStoreFactory.make(for: settings.source), source: settings.source,
                                    context: modelContext, today: DebugOptions.now)
        let system = client.prefersCompactContext
            ? HealthReportText.compactSystemPrompt(for: report) + "\n\nĐây là hỏi đáp: trả lời ngắn (≤ 5 câu), dẫn số.\n\nSỐ LIỆU:\n" + HealthReportText.compact(report)
            : HealthReportText.chatSystemPrompt(for: report, today: DebugOptions.now)
        let runner = AIConversationRunner(client: client, tools: client.supportsTools ? tools : nil, system: system)
        task = Task {
            do {
                let text = try await runner.run(history: history) { ev in
                    switch ev {
                    case .text(let t): streaming += t
                    case .status(let s): status = s
                    }
                }
                let item = ChatItem(id: UUID(), role: .assistant, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
                messages.append(item); persist(item)
            } catch is CancellationError {
                if !streaming.isEmpty { let item = ChatItem(id: UUID(), role: .assistant, text: streaming); messages.append(item); persist(item) }
            } catch {
                self.error = error.localizedDescription
            }
            streaming = ""; status = nil; running = false
        }
    }

    private func persist(_ item: ChatItem) {
        let m = AIChatMessage(contextKey: contextKey, role: item.role == .user ? "user" : "assistant", text: item.text)
        m.id = item.id
        modelContext.insert(m)
        try? modelContext.save()
    }

    private func clear() {
        task?.cancel()
        AIChatMessage.clear(contextKey, in: modelContext)
        messages = []; streaming = ""; error = nil
    }
}

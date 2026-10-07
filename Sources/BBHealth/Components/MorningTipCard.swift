import SwiftUI
import SwiftData

/// Thẻ **"Lời khuyên sáng nay"** ở màn Hôm nay (T-032): AI đọc đêm qua + hôm nay (3–4 câu), tự chạy
/// 1 lần/ngày khi đã thiết lập AI và bật trong Cài đặt → Trợ lý AI; lưu `AIAnalysis` (mode "morning").
struct MorningTipCard: View {
    let date: Date
    /// Màn Hôm nay đã tải xong số (mới chạy AI, tránh gửi số rỗng).
    let ready: Bool

    @Environment(\.modelContext) private var modelContext
    @State private var ai = AISettings.shared
    @State private var settings = AppSettings.shared
    @State private var text = ""
    @State private var running = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var showingChat = false
    @State private var attemptedDay: Date?

    private var client: (any AIClient)? {
        if let c = ai.makeClient() { return c }
        return HealthStoreFactory.useMock && ai.kind != .none ? MockAIClient() : nil
    }
    private var period: ReportPeriod { ReportPeriod(kind: .day, end: date) }

    var body: some View {
        if ai.morningTip, client != nil {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionHeader(title: "Lời khuyên sáng nay", symbol: "sparkles", tint: Theme.brand)
                    if running { ProgressView().controlSize(.small) }
                }
                if !text.isEmpty {
                    AIMarkdownText(text: text)
                } else if running {
                    Text("AI đang đọc đêm qua của bạn…").font(.callout).foregroundStyle(Theme.textSecondary)
                } else if let e = error {
                    Label(e, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Theme.improve)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Chạm để AI đọc đêm qua và gợi ý cho hôm nay.").font(.callout).foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: 10) {
                    if !running {
                        Button { generate(force: true) } label: {
                            Label(text.isEmpty ? "Xem lời khuyên" : "Làm mới", systemImage: text.isEmpty ? "sparkles" : "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(Theme.brand)
                    } else {
                        Button { task?.cancel() } label: { Label("Dừng", systemImage: "stop.fill").frame(maxWidth: .infinity) }
                            .buttonStyle(.bordered).tint(Theme.neutral)
                    }
                    Button { showingChat = true } label: {
                        Label("Hỏi tiếp", systemImage: "bubble.left.and.text.bubble.right.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.brand)
                }
                .controlSize(.regular)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.brand)
            .sheet(isPresented: $showingChat) { AIDayChatSheet(date: date) }
            .task(id: "\(ready)-\(HealthDataTools.ymd(date))") { await loadOrGenerate() }
        }
    }

    private func loadOrGenerate() async {
        if let s = AIAnalysis.latest(for: period, mode: "morning", in: modelContext) {
            text = s.text
            return
        }
        // Tự chạy 1 lần/ngày (sau khi Hôm nay đã có số); lỗi thì để nút cho anh bấm lại.
        guard ready, attemptedDay != period.end, ai.hasConsented(ai.kind) || HealthStoreFactory.useMock else { return }
        attemptedDay = period.end
        generate(force: false)
    }

    private func generate(force: Bool) {
        guard let client, !running else { return }
        task?.cancel()
        running = true; error = nil; text = ""
        let source = settings.source
        let p = period
        task = Task {
            let r = await HealthReportBuilder.build(period: p, provider: HealthStoreFactory.make(for: source),
                                                    source: source, context: modelContext, now: DebugOptions.now)
            guard r.hasAnyData || force else { running = false; return }
            let compact = client.prefersCompactContext
            let system = (compact ? HealthReportText.compactSystemPrompt(for: r) : HealthReportText.aiPrompt(for: r)) + """


            Đây là LỜI KHUYÊN BUỔI SÁNG, rất ngắn: tối đa 4 câu hoặc 3 gạch đầu dòng "- ", khoảng 60–90 chữ. \
            Câu 1: đêm qua thế nào (dẫn số: giờ ngủ, thức giấc, nhịp nghỉ/HRV nếu có) và so với mấy ngày trước. \
            Sau đó 1–2 việc cụ thể cho HÔM NAY (ăn, ngủ trưa, vận động, tránh gì). Không chào hỏi, không tiêu đề, không dấu #.
            """
            do {
                for try await chunk in client.textStream(system: system,
                                                         messages: [AIMessage(role: .user, text: compact ? HealthReportText.compact(r) : HealthReportText.markdown(r, includePrompt: false))],
                                                         maxTokens: 1024) {
                    text += chunk
                }
                let a = AIAnalysis(kind: .day, periodEnd: p.end, provider: client is MockAIClient ? "AI giả lập" : ai.kind.title,
                                   model: client.model, text: text.trimmingCharacters(in: .whitespacesAndNewlines), mode: "morning")
                modelContext.insert(a)
                try? modelContext.save()
            } catch is CancellationError {
            } catch {
                self.error = error.localizedDescription
            }
            running = false
        }
    }
}

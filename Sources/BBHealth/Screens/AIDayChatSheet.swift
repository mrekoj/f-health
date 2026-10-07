import SwiftUI
import SwiftData

/// Mở **Hỏi AI** cho một NGÀY (từ Giấc ngủ chi tiết / Nhịp tim — T-032): tự dựng báo cáo ngày rồi vào chat,
/// gửi sẵn câu hỏi đầu nếu có.
struct AIDayChatSheet: View {
    let date: Date
    var initialQuestion: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var settings = AppSettings.shared
    @State private var report: HealthReport?

    var body: some View {
        Group {
            if let r = report {
                AIChatView(report: r, initialQuestion: initialQuestion)
            } else {
                NavigationStack {
                    ProgressView("Đang gom số liệu ngày…").controlSize(.large)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background.ignoresSafeArea())
                        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } } }
                }
            }
        }
        .task {
            let source = settings.source
            report = await HealthReportBuilder.build(period: ReportPeriod(kind: .day, end: date),
                                                     provider: HealthStoreFactory.make(for: source),
                                                     source: source, context: modelContext, now: DebugOptions.now)
        }
    }
}

/// Nút "Hỏi AI" dùng trên toolbar các màn chi tiết — ẩn khi chưa thiết lập AI (trừ máy ảo).
struct AskAIToolbarButton: View {
    let date: Date
    var question: String?
    @State private var ai = AISettings.shared
    @State private var showing = false

    private var available: Bool { ai.isReady || (HealthStoreFactory.useMock && ai.kind != .none) }

    var body: some View {
        if available {
            Button { showing = true } label: { Label("Hỏi AI", systemImage: "sparkles") }
                .sheet(isPresented: $showing) { AIDayChatSheet(date: date, initialQuestion: question) }
        }
    }
}

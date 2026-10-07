import SwiftUI

/// Màn **Trợ lý AI** trong Cài đặt (T-026): chọn hãng, dán khoá (Keychain), chọn model, kiểm tra kết nối.
/// Mỗi người dùng tự dán khoá của mình — app không có máy chủ, không dùng khoá của chủ app.
struct AISettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var ai = AISettings.shared
    @State private var keyDraft = ""
    @State private var modelDraft = ""
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    providerList
                    if ai.kind == .appleOnDevice {
                        onDeviceCard
                        if ai.isReady { testCard; optionsCard }
                        privacyCard
                    } else if ai.kind != .none {
                        if ai.kind == .gemini { geminiGuide }
                        keyCard
                        modelCard
                        testCard
                        optionsCard
                        privacyCard
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Trợ lý AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() }.fontWeight(.semibold) } }
            .scrollDismissesKeyboard(.interactively)
            .onAppear(perform: loadDrafts)
            .onChange(of: ai.kind) { loadDrafts(); testResult = nil }
        }
    }

    private func loadDrafts() {
        keyDraft = ai.apiKey(for: ai.kind) ?? ""
        modelDraft = ai.model(for: ai.kind)
    }

    // MARK: - Chọn hãng

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chọn AI phân tích báo cáo cho anh. Ai không có tài khoản AI vẫn dùng được Báo cáo + Sao chép; có tài khoản Google là dùng Gemini miễn phí.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.s)
            ForEach(AIProviderKind.allCases) { k in
                let selected = ai.kind == k
                Button { ai.kind = k } label: {
                    HStack(alignment: .top, spacing: 12) {
                        IconBadge(symbol: k.symbol, tint: selected ? Theme.brand : Theme.neutral)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(k.title).font(.cardTitle).foregroundStyle(Theme.textPrimary)
                            Text(k.subtitle).font(.callout).foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.title2).foregroundStyle(selected ? Theme.brand : Theme.textTertiary)
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(tint: selected ? Theme.brand : nil)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - AI trên iPhone (T-028)

    private var onDeviceCard: some View {
        let st = OnDeviceAI.status
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Apple Intelligence trên máy", symbol: "iphone.gen3", tint: Theme.brand)
                StatusChip(level: st.isAvailable ? .good : .caution, compact: true)
            }
            Text(st.text).font(.callout).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Text("Mô hình nhỏ chạy trong máy: phân tích ngắn gọn, không tự tra cứu thêm ngày khác, chỉ nhận gói số liệu rút gọn. Muốn phân tích sâu hơn thì chọn Gemini/Claude.")
                .font(.footnote).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.brand)
    }

    // MARK: - Hướng dẫn lấy khoá Gemini miễn phí

    private var geminiGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Lấy khoá Gemini miễn phí (~2 phút)", symbol: "key.fill", tint: Theme.good)
            step(1, "Bấm nút dưới → đăng nhập tài khoản Google.")
            step(2, "Bấm **Create API key** (Tạo khoá) → chọn dự án bất kỳ hoặc tạo mới.")
            step(3, "Bấm biểu tượng sao chép cạnh khoá (bắt đầu bằng **AQ.** hoặc **AIza**), quay lại đây dán vào ô Khoá.")
            Button { if let u = AIProviderKind.gemini.keyURL { openURL(u) } } label: {
                Label("Mở trang lấy khoá", systemImage: "safari.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Theme.good).controlSize(.large)
            Text("Không cần thẻ ngân hàng. Gói miễn phí đủ cho một người dùng hằng ngày (vài trăm lượt/ngày).")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.good)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.number(15)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Theme.good, in: Circle())
            Text(LocalizedStringKey(text)).font(.callout).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Khoá

    private var keyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "Khoá API", symbol: "lock.fill")
                if ai.apiKey(for: ai.kind) != nil { StatusChip(level: .good, compact: true) }
            }
            if ai.kind == .openAICompatible {
                Text("Địa chỉ máy chủ").font(.label).foregroundStyle(Theme.textSecondary)
                TextField("https://api.openai.com/v1", text: $ai.baseURL)
                    .font(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .padding(12)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                Text("Ollama trong nhà: http://<IP máy tính>:11434/v1 (không cần khoá).")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            SecureField(ai.kind == .gemini ? "AQ.… hoặc AIza…" : (ai.kind == .claude ? "sk-ant-…" : "sk-…"), text: $keyDraft)
                .font(.system(.callout, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            HStack(spacing: 10) {
                Button {
                    if let s = UIPasteboard.general.string { keyDraft = s.trimmingCharacters(in: .whitespacesAndNewlines) }
                    ai.setAPIKey(keyDraft, for: ai.kind); testResult = nil
                } label: { Label("Dán & lưu", systemImage: "doc.on.clipboard").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(Theme.brand)
                Button {
                    ai.setAPIKey(keyDraft, for: ai.kind); testResult = nil
                } label: { Label("Lưu", systemImage: "checkmark").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).tint(Theme.brand)
                if ai.apiKey(for: ai.kind) != nil {
                    Button(role: .destructive) {
                        ai.setAPIKey(nil, for: ai.kind); keyDraft = ""; testResult = nil
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.bordered).tint(Theme.improve)
                }
            }
            .controlSize(.large)
            if ai.kind != .gemini, let u = ai.kind.keyURL {
                Button { openURL(u) } label: { Label("Mở trang lấy khoá", systemImage: "safari") }
                    .font(.callout).tint(Theme.brand)
            }
            Text("Khoá lưu trong Keychain của máy, chỉ dùng để gọi \(ai.kind.title).")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Model

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Mô hình", symbol: "cpu")
            ForEach(ai.kind.suggestedModels, id: \.id) { m in
                Button { modelDraft = m.id; ai.setModel(m.id, for: ai.kind) } label: {
                    HStack {
                        Text(m.label).font(.callout).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        if ai.model(for: ai.kind) == m.id {
                            Image(systemName: "checkmark").foregroundStyle(Theme.brand).fontWeight(.bold)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            TextField("Tên mô hình khác", text: $modelDraft)
                .font(.system(.callout, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                .onSubmit { ai.setModel(modelDraft, for: ai.kind) }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Kiểm tra

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { runTest() } label: {
                HStack {
                    if testing { ProgressView().tint(.white) }
                    Text(testing ? "Đang kiểm tra…" : "Kiểm tra kết nối").font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Theme.brand).controlSize(.large)
            .disabled(testing || !ai.isReady)
            if let r = testResult {
                Label(r.text, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(r.ok ? Theme.good : Theme.improve)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !ai.isReady {
                Text("Dán khoá trước rồi kiểm tra.").font(.footnote).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func runTest() {
        if modelDraft != ai.model(for: ai.kind) { ai.setModel(modelDraft, for: ai.kind) }
        guard let client = ai.makeClient() else { return }
        testing = true; testResult = nil
        Task {
            do {
                let reply = try await client.complete(
                    system: "Trả lời đúng một câu tiếng Việt thật ngắn.",
                    messages: [AIMessage(role: .user, text: "Chào bạn, bạn là mô hình nào?")])
                testResult = (true, "Kết nối được \(ai.summary). AI trả lời: \(reply.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))")
            } catch {
                testResult = (false, error.localizedDescription)
            }
            testing = false
        }
    }

    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "AI ở màn Hôm nay", symbol: "sun.max.fill", tint: Theme.good)
            Toggle("Lời khuyên sáng nay (AI đọc đêm qua, 1 lần/ngày)", isOn: $ai.morningTip)
                .font(.callout).tint(Theme.brand)
            Text("Mỗi ngày tốn 1 lượt AI. Tắt nếu muốn tiết kiệm lượt miễn phí.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.good)
    }

    private var privacyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Quyền riêng tư", symbol: "hand.raised.fill", tint: Theme.caution)
            Text(ai.kind.privacyNote).font(.callout).foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("App chỉ gửi khi anh bấm Nhờ AI phân tích. Lời khuyên của AI chỉ để tham khảo, không thay bác sĩ.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.caution)
    }
}

#Preview { AISettingsView() }

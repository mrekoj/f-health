import SwiftUI
import SwiftData

/// Màn **Báo cáo sức khoẻ** (T-025): Ngày/Tuần/Tháng — tổng quan, ô số, nhận xét tự động theo ngưỡng
/// cá nhân, gợi ý, số liệu từng ngày; khối **AI phân tích** (T-026, Gemini/Claude/OpenAI bằng khoá của người dùng) + Sao chép / Chia sẻ / Xem nội dung.
/// Mức 0 của Trợ lý AI: không cần tài khoản, không gửi gì đi cho tới khi anh bấm.
struct ReportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ReportKind
    @State private var endDate: Date
    @State private var report: HealthReport?
    @State private var loading = false
    @State private var showingText = false
    @State private var showingInfo = false
    @State private var toast: String?
    // T-026: AI phân tích
    @State private var ai = AISettings.shared
    @State private var aiText = ""
    @State private var aiRunning = false
    @State private var aiError: String?
    @State private var aiTask: Task<Void, Never>?
    @State private var saved: AIAnalysis?
    @State private var showingAISettings = false
    @State private var askingConsent = false
    @State private var aiExpanded = false
    @State private var showingChat = false
    @State private var aiMode = "quick"
    @State private var pendingDeep = false
    @State private var settings = AppSettings.shared

    init(kind: ReportKind = .week, endDate: Date = DebugOptions.now) {
        _kind = State(initialValue: kind)
        _endDate = State(initialValue: Calendar.current.startOfDay(for: endDate))
    }

    private var period: ReportPeriod { ReportPeriod(kind: kind, end: endDate) }
    private var isLatest: Bool { endDate >= Calendar.current.startOfDay(for: DebugOptions.now) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    kindPicker
                    dateRow
                    if let r = report, !loading {
                        if r.hasAnyData {
                            overallCard(r)
                            aiAnalysisCard(r)
                            statsGrid(r)
                            findingsSection(r)
                            adviceCard(r)
                            daysSection(r)
                        } else {
                            emptyCard(r)
                        }
                        aiCard(r)
                        footer(r)
                    } else {
                        ProgressView("Đang tổng hợp…").controlSize(.large)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .defaultScrollAnchor(DebugOptions.scrollToBottom ? .bottom : .top)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Báo cáo sức khoẻ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingInfo = true } label: { Image(systemName: "questionmark.circle") }
                }
                ToolbarItem(placement: .topBarTrailing) { Button("Đóng") { dismiss() } }
            }
            .task(id: period) { await load() }
            .onChange(of: settings.source) { Task { await load() } }
            .sheet(isPresented: $showingText) { if let r = report { ReportTextSheet(report: r) } }
            .sheet(isPresented: $showingInfo) { infoSheet }
            .sheet(isPresented: $showingAISettings) { AISettingsView() }
            .sheet(isPresented: $showingChat) { if let r = report { AIChatView(report: r) } }
            .alert("Gửi báo cáo cho \(ai.kind.title)?", isPresented: $askingConsent) {
                Button("Đồng ý gửi") {
                    ai.setConsented(ai.kind)
                    if let r = report { runAI(r, deep: pendingDeep) }
                }
                Button("Thôi", role: .cancel) {}
            } message: { Text(ai.kind.privacyNote) }
            .overlay(alignment: .bottom) { toastView }
        }
    }

    private func load() async {
        aiTask?.cancel()
        aiRunning = false
        aiError = nil
        loading = true
        let source = settings.source
        report = await HealthReportBuilder.build(period: period,
                                                 provider: HealthStoreFactory.make(for: source),
                                                 source: source, context: modelContext)
        saved = AIAnalysis.latest(for: period, mode: aiMode, in: modelContext)
        aiText = saved?.text ?? ""
        loading = false
        if DebugOptions.showReportText, !showingText { showingText = true }
        if DebugOptions.autoAI, saved == nil, let r = report { runAI(r, deep: DebugOptions.deepAI) }
        if DebugOptions.chatQuestion != nil, report != nil { showingChat = true }
    }

    // MARK: - AI phân tích (T-026)

    /// Client dùng được: cấu hình thật; trên máy ảo chưa có khoá thì AI giả lập (để xem giao diện).
    private var client: (any AIClient)? {
        if let c = ai.makeClient() { return c }
        return HealthStoreFactory.useMock && ai.kind != .none ? MockAIClient() : nil
    }

    private func requestAI(_ r: HealthReport, deep: Bool = false) {
        guard client != nil else { showingAISettings = true; return }
        if !ai.hasConsented(ai.kind) && !HealthStoreFactory.useMock { pendingDeep = deep; askingConsent = true; return }
        runAI(r, deep: deep)
    }

    /// Đổi chế độ nhanh/sâu: nạp bài đã lưu của chế độ đó (nếu có).
    private func switchMode(_ mode: String) {
        guard !aiRunning else { return }
        aiMode = mode
        saved = AIAnalysis.latest(for: period, mode: mode, in: modelContext)
        aiText = saved?.text ?? ""
        aiExpanded = false
    }

    private func runAI(_ r: HealthReport, deep: Bool = false) {
        aiMode = deep ? "deep" : "quick"
        let client: any AIClient = (deep ? ai.makeClient(deep: true) : nil) ?? self.client ?? MockAIClient()
        aiTask?.cancel()
        aiText = ""
        aiError = nil
        aiRunning = true
        let compact = client.prefersCompactContext
        let system = compact ? HealthReportText.compactSystemPrompt(for: r)
            : (deep ? HealthReportText.deepSystemPrompt(for: r) : HealthReportText.systemPrompt(for: r))
        let user = compact ? HealthReportText.compact(r) : HealthReportText.markdown(r, includePrompt: false)
        let period = r.period
        let mode = aiMode
        let providerTitle = client is MockAIClient ? "AI giả lập" : ai.kind.title
        aiTask = Task {
            do {
                for try await chunk in client.textStream(system: system, messages: [AIMessage(role: .user, text: user)],
                                                         maxTokens: deep ? 8192 : 4096) {
                    aiText += chunk
                }
                let a = AIAnalysis(kind: period.kind, periodEnd: period.end, provider: providerTitle,
                                   model: client.model, text: aiText.trimmingCharacters(in: .whitespacesAndNewlines), mode: mode)
                modelContext.insert(a)
                try? modelContext.save()
                saved = a
            } catch is CancellationError {
            } catch {
                aiError = error.localizedDescription
                if aiText.isEmpty { aiText = saved?.text ?? "" }
            }
            aiRunning = false
        }
    }

    private func aiAnalysisCard(_ r: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: aiMode == "deep" ? "AI phân tích sâu" : "AI phân tích", symbol: "sparkles")
                if aiRunning { ProgressView().controlSize(.small) }
            }
            if client != nil {
                Picker("Chế độ", selection: Binding(get: { aiMode }, set: { switchMode($0) })) {
                    Text("Nhanh").tag("quick")
                    Text("Sâu").tag("deep")
                }
                .pickerStyle(.segmented).disabled(aiRunning)
            }
            if !aiText.isEmpty {
                let md = AIMarkdownText(text: aiText, limit: aiRunning || aiExpanded ? nil : 9)
                md
                if !aiRunning && md.lineCount > 9 {
                    Button { withAnimation { aiExpanded.toggle() } } label: {
                        Label(aiExpanded ? "Thu gọn" : "Xem hết bài phân tích",
                              systemImage: aiExpanded ? "chevron.up" : "chevron.down")
                            .font(.callout.weight(.semibold))
                    }
                    .tint(Theme.brand)
                }
                if let s = saved, !aiRunning {
                    Text("\(s.provider) · \(s.model) · \(TodayViewModel.timeAndDate(s.createdAt)). Chỉ để tham khảo, không thay bác sĩ.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                }
            } else if !aiRunning {
                Text(client == nil
                     ? "Thiết lập AI một lần (Gemini có gói miễn phí) để app tự phân tích báo cáo này cho anh — không cần sao chép sang ứng dụng khác."
                     : "Nhờ \(ai.kind.title) đọc hồ sơ + số liệu kỳ này và viết nhận định, mối liên hệ, việc nên làm.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Đang gửi báo cáo cho AI…").font(.callout).foregroundStyle(Theme.textSecondary)
            }
            if let e = aiError {
                Label(e, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Theme.improve)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if aiRunning {
                Button(role: .cancel) { aiTask?.cancel(); aiRunning = false } label: {
                    Label("Dừng", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.neutral).controlSize(.large)
            } else {
                Button { requestAI(r, deep: aiMode == "deep") } label: {
                    Label(client == nil ? "Thiết lập AI"
                          : (aiText.isEmpty ? (aiMode == "deep" ? "Phân tích sâu (model mạnh)" : "Nhờ AI phân tích") : "Phân tích lại"),
                          systemImage: client == nil ? "gearshape.fill" : (aiText.isEmpty ? "sparkles" : "arrow.clockwise"))
                        .font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).tint(Theme.brand).controlSize(.large)
                if aiMode == "deep" && aiText.isEmpty && client != nil {
                    Text("Sâu: dùng \(ai.kind.deepModel), đọc cả bảng theo tuần/ngày, chấm tiến độ mục tiêu, so kỳ trước, đề xuất thí nghiệm 2 tuần. Lâu hơn (1–2 phút) và tốn lượt hơn.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
                if client != nil {
                    Button { showingChat = true } label: {
                        Label("Hỏi AI về kỳ này", systemImage: "bubble.left.and.text.bubble.right.fill")
                            .font(.title3.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered).tint(Theme.brand).controlSize(.large)
                    Button { showingAISettings = true } label: {
                        Text("Đang dùng: \(client is MockAIClient ? "AI giả lập (máy ảo)" : ai.summary) — đổi")
                            .font(.footnote)
                    }
                    .tint(Theme.textSecondary)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.brand)
    }

    // MARK: - Chọn kỳ

    private var kindPicker: some View {
        Picker("Kỳ", selection: $kind) {
            ForEach(ReportKind.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.top, Theme.Space.s)
    }

    private var dateRow: some View {
        HStack {
            Button { endDate = period.shifted(by: -1).end } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 40, height: 36)
            }
            .buttonStyle(.bordered).tint(Theme.brand)
            Spacer()
            VStack(spacing: 2) {
                Text(period.title)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(period.rangeText)
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { endDate = min(period.shifted(by: 1).end, Calendar.current.startOfDay(for: DebugOptions.now)) } label: {
                Image(systemName: "chevron.right").font(.headline).frame(width: 40, height: 36)
            }
            .buttonStyle(.bordered).tint(Theme.brand)
            .disabled(isLatest)
        }
    }

    // MARK: - Tổng quan

    private func overallCard(_ r: HealthReport) -> some View {
        HStack(alignment: .top, spacing: 14) {
            IconBadge(symbol: r.overallLevel == .good ? "checkmark.seal.fill" : (r.overallLevel == .bad ? "exclamationmark.triangle.fill" : "eye.fill"),
                      tint: r.overallLevel.color, size: 48)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Đánh giá chung").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    StatusChip(level: r.overallLevel)
                }
                Text(r.overallText)
                    .font(.callout).foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: r.overallLevel.color)
    }

    private func statsGrid(_ r: HealthReport) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.m), GridItem(.flexible(), spacing: Theme.Space.m)],
                  spacing: Theme.Space.m) {
            ForEach(r.stats) { s in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: s.symbol).font(.caption.weight(.bold)).foregroundStyle(s.level.color)
                        Text(s.title).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(s.value).font(.number(26)).foregroundStyle(Theme.textPrimary)
                        Text(s.unit).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(2)
                    }
                    if let d = s.delta {
                        Text(d).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1)
                    }
                    if s.level != .unknown { StatusChip(level: s.level, compact: true) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .card(tint: s.level.color, radius: Theme.Radius.small)
            }
        }
    }

    // MARK: - Nhận xét & gợi ý

    private func findingsSection(_ r: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Nhận xét theo ngưỡng của bạn", symbol: "text.magnifyingglass")
            ForEach(r.findings) { f in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(f.level.color).frame(width: 10, height: 10).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(f.title).font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            if f.isDoctor {
                                TagChip(text: "BS dặn", symbol: "stethoscope", tint: Theme.improve)
                                    .scaleEffect(0.85, anchor: .leading)
                            }
                        }
                        Text(f.detail).font(.callout).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(tint: f.level == .good ? nil : f.level.color, radius: Theme.Radius.small)
            }
        }
    }

    private func adviceCard(_ r: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Gợi ý", symbol: "lightbulb.fill", tint: Theme.caution)
            ForEach(Array(r.advice.enumerated()), id: \.offset) { i, a in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)").font(.number(15)).foregroundStyle(Theme.caution).frame(width: 20)
                    Text(a).font(.callout).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("Gợi ý tự động theo ngưỡng cá nhân — chỉ để tham khảo, không thay bác sĩ.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.caution)
    }

    // MARK: - Từng ngày

    private func daysSection(_ r: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: r.period.kind == .day ? "Nhật ký trong ngày" : "Từng ngày", symbol: "calendar")
            if r.period.kind == .day, let d = r.days.first {
                dayDiary(d)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(r.days.reversed())) { d in
                        dayRow(d)
                        if d.id != r.days.first?.id { Divider().overlay(Theme.hairline) }
                    }
                }
                .padding(.vertical, 4)
                .card()
                Text("Giấc ngủ ghi ở ngày = đêm trước ngày đó. Chấm đỏ = có rượu bia · chấm vàng = có triệu chứng.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func dayRow(_ d: ReportDay) -> some View {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EE d/M"
        return HStack(spacing: 10) {
            Text(f.string(from: d.date))
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary).frame(width: 64, alignment: .leading)
            cell(d.sleepHours.map { TodayViewModel.decimal($0, digits: 1) + "g" }, level: Thresholds.sleep(hours: d.sleepHours), width: 48)
            cell(d.restingHR.map { "\(Int($0.rounded()))" }, level: Thresholds.restingHeartRate(bpm: d.restingHR), width: 34)
            cell(d.steps.map { TodayViewModel.grouped($0) }, level: Thresholds.steps(d.steps), width: 56)
            cell(d.weightKg.map { TodayViewModel.decimal($0, digits: 1) }, level: Thresholds.bodyMass(kg: d.weightKg), width: 40)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if d.hadAlcohol { Circle().fill(Theme.improve).frame(width: 8, height: 8) }
                if !d.symptoms.isEmpty { Circle().fill(Theme.caution).frame(width: 8, height: 8) }
                if d.napCount > 0 { Image(systemName: "powersleep").font(.caption2).foregroundStyle(Theme.sleep) }
            }
            .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func cell(_ text: String?, level: MetricLevel, width: CGFloat) -> some View {
        Text(text ?? "–")
            .font(.system(.footnote, design: .rounded).weight(.medium)).monospacedDigit()
            .foregroundStyle(text == nil ? Theme.textTertiary : level.color)
            .frame(width: width, alignment: .leading)
    }

    private func dayDiary(_ d: ReportDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !d.meals.isEmpty { diaryLine("fork.knife", Theme.meal, "Bữa ăn: " + d.meals.joined(separator: "; ")) }
            if d.hadAlcohol { diaryLine("wineglass.fill", Theme.improve, "Rượu bia: \(Int(d.alcoholUnits.rounded())) ly" + (d.alcoholLatest.map { " (\(TodayViewModel.time($0)))" } ?? "")) }
            if !d.symptoms.isEmpty { diaryLine("stethoscope", Theme.caution, "Triệu chứng: " + d.symptoms.joined(separator: ", ")) }
            if d.napCount > 0 { diaryLine("powersleep", Theme.sleep, "Ngủ trưa: \(d.napCount) giấc · \(d.napMinutes) phút") }
            if d.breathingSessions > 0 { diaryLine("wind", Theme.brand, "Bài thở: \(d.breathingSessions) lần" + (d.breathingDrops.isEmpty ? "" : " (hạ \(d.breathingDrops.map(String.init).joined(separator: ", ")) nhịp)")) }
            ForEach(d.heartEvents, id: \.self) { diaryLine("heart.text.square.fill", Theme.heart, $0) }
            if d.meals.isEmpty && !d.hadAlcohol && d.symptoms.isEmpty && d.napCount == 0 && d.breathingSessions == 0 && d.heartEvents.isEmpty {
                Text("Chưa ghi gì hôm nay. Ghi bữa ăn, rượu bia, triệu chứng ở tab Ghi nhanh để báo cáo đầy đủ hơn.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func diaryLine(_ symbol: String, _ tint: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.subheadline).foregroundStyle(tint).frame(width: 20)
            Text(text).font(.callout).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func emptyCard(_ r: HealthReport) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(Theme.textTertiary)
            Text("Chưa có số liệu cho kỳ này").font(.cardTitle).foregroundStyle(Theme.textPrimary)
            Text(r.overallText).font(.callout).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .padding(Theme.Space.xl).frame(maxWidth: .infinity).card()
    }

    // MARK: - Mang báo cáo sang chỗ khác (sao chép / chia sẻ / xem nội dung)

    private func aiCard(_ r: HealthReport) -> some View {
        let text = HealthReportText.markdown(r, includePrompt: true)
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Gửi báo cáo đi nơi khác", symbol: "square.and.arrow.up")
            Text("Gói hồ sơ + số liệu + nhận xét (kèm câu hỏi mẫu) — dán cho bác sĩ, người nhà, hoặc ứng dụng AI khác.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = text
                    showToast("Đã sao chép báo cáo")
                } label: { Label("Sao chép", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }
                ShareLink(item: text, subject: Text("Báo cáo sức khoẻ \(r.period.rangeText)")) {
                    Label("Chia sẻ", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered).tint(Theme.brand).controlSize(.large)
            HStack(spacing: 10) {
                Button {
                    let name = ReportExporter.saveReport(r, aiText: aiText, aiLabel: saved.map { "\($0.provider) · \($0.model)" })
                    showToast("Đã lưu \(name) — app Tệp → BBHealth")
                } label: { Label("Lưu vào Tệp", systemImage: "folder").frame(maxWidth: .infinity) }
                Button { showingText = true } label: {
                    Label("Xem nội dung", systemImage: "doc.text.magnifyingglass").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered).tint(Theme.brand).controlSize(.large)
            Text("Tệp: Trên iPhone của tôi → BBHealth (health.csv mỗi ngày + báo cáo .md). Kéo sang iCloud Drive nếu cần.")
                .font(.footnote).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func footer(_ r: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nguồn: \(r.sourceTitle)", systemImage: settings.source.symbol).foregroundStyle(Theme.brand)
            Text("Tổng hợp lúc \(TodayViewModel.time(r.generatedAt)). Hồ sơ dùng cho ngưỡng: \(r.profile.displayName.isEmpty ? "chưa đặt tên" : r.profile.displayName) — sửa trong Cài đặt → Hồ sơ của tôi.")
            if r.isMock {
                Label("Đang hiển thị số giả lập (máy ảo)", systemImage: "info.circle").foregroundStyle(Theme.caution)
            }
        }
        .font(.footnote).foregroundStyle(Theme.textTertiary)
    }

    // MARK: - Phụ

    private func showToast(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut) { toast = nil }
        }
    }

    @ViewBuilder private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Theme.brandDeep, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var infoSheet: some View {
        InfoSheet(
            title: "Báo cáo này là gì?",
            symbol: "doc.text.magnifyingglass",
            tint: Theme.brand,
            sections: [
                .init(title: "App tự tổng hợp", symbol: "chart.bar.doc.horizontal.fill", tint: Theme.brand,
                      text: "Gom số đo từ vòng (ngủ, nhịp tim, bước, cân, HRV…) và nhật ký anh ghi (bữa ăn, rượu bia, triệu chứng, ngủ trưa, bài thở) theo ngày, 7 ngày hoặc 30 ngày; so với kỳ trước; chấm xanh/vàng/đỏ theo ngưỡng riêng trong Hồ sơ của tôi."),
                .init(title: "Nhận xét tự động", symbol: "text.magnifyingglass", tint: Theme.caution,
                      text: "Là quy tắc đời thường (ngủ thiếu bao nhiêu, giờ ngủ có đều không, rượu bia ảnh hưởng đêm sau thế nào, cân đi đúng hướng chưa…) — không phải chẩn đoán. Số nào thiếu thì bỏ qua, không bịa."),
                .init(title: "Nhờ AI", symbol: "sparkles", tint: Theme.good,
                      text: "Bấm Nhờ AI phân tích: app gửi hồ sơ + số liệu kỳ này cho AI anh đã chọn (Cài đặt → Trợ lý AI; Gemini có gói miễn phí) và hiện bài phân tích ngay tại đây, lưu lại để lần sau mở không tốn lượt. Bấm Xem nội dung sẽ gửi để biết chính xác gửi gì."),
            ])
    }
}

// MARK: - Sheet xem/sao chép văn bản sẽ gửi

struct ReportTextSheet: View {
    let report: HealthReport
    @Environment(\.dismiss) private var dismiss
    @State private var includePrompt = true
    @State private var copied = false

    private var text: String { HealthReportText.markdown(report, includePrompt: includePrompt) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Kèm câu hỏi mẫu cho AI", isOn: $includePrompt)
                        .font(.callout).tint(Theme.brand)
                    Text(text)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Nội dung sẽ gửi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = text
                        copied = true
                    } label: { Label(copied ? "Đã chép" : "Sao chép", systemImage: copied ? "checkmark" : "doc.on.doc") }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Xong") { dismiss() } }
            }
        }
    }
}

#Preview {
    ReportView()
        .modelContainer(for: [DailyLog.self, LogEntry.self, HeartEvent.self, NapLog.self, LiveSession.self], inMemory: true)
}

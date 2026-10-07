import SwiftUI

/// Màn Hôm nay: lời chào + tóm tắt, thẻ lớn Giấc ngủ, Nhịp tim nghỉ / Bước chân / Cân nặng, Bữa tiếp theo.
struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TodayViewModel(date: DebugOptions.now)
    /// Đánh dấu lần hiện màn ĐẦU TIÊN (do `.task` lo) để `.onAppear` chỉ tải lại ở các lần hiện LẠI.
    @State private var didFirstAppear = false
    @State private var explaining: Metric?
    @State private var showingSleepDetail = false
    @State private var showingHeartDetail = false
    @State private var showingHistory = false
    @State private var showingNaps = false
    @State private var showingNapInfo = false
    @State private var settings = AppSettings.shared
    @State private var auth = GoogleAuth.shared
    @State private var profileSettings = ProfileSettings.shared
    @State private var showingProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header
                    if profileSettings.profile.isEmpty { onboardingCard }
                    switch model.state {
                    case .idle, .loading:
                        loadingView
                    case .needsAuthorization:
                        authorizationView
                    case .failed(let message):
                        errorView(message)
                    case .loaded:
                        content
                        footer
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .defaultScrollAnchor(DebugOptions.scrollToBottom ? .bottom : .top)
            .background(background)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable {
                await model.refresh()
                if model.state == .loaded { await model.autoLogNaps(into: modelContext) }
            }
            .task {
                await model.loadIfNeeded()
                // Tải xong → tự quét + lưu giấc ngủ trưa gần đây (không cần ghi tay).
                if model.state == .loaded {
                    await model.autoLogNaps(into: modelContext)
                    ReportExporter.writeToday(from: model, context: modelContext)   // T-033: health.csv mỗi ngày (app Tệp)
                }
                if explaining == nil, let m = DebugOptions.showExplain { explaining = m }
                if DebugOptions.showSleepDetail { showingSleepDetail = true }
                if DebugOptions.showHeartDetail { showingHeartDetail = true }
                if DebugOptions.showSleepHistory { showingHistory = true }
                if DebugOptions.showNaps { showingNaps = true }
            }
            .onChange(of: settings.source) { Task { await model.reload() } }
            .onChange(of: auth.isConnected) { Task { await model.reload() } }
            // App vào foreground → tự tải lại (hết cảnh phải kéo-làm-mới nhiều lần vì Fitbit đồng bộ dần).
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await model.refreshOnForeground()
                    if model.state == .loaded { await model.autoLogNaps(into: modelContext) }
                }
            }
            // Màn Hôm nay hiện LẠI (chuyển tab rồi quay về) → tải lại; lần đầu để `.task` lo.
            .onAppear {
                guard didFirstAppear else { didFirstAppear = true; return }
                Task {
                    await model.refreshOnForeground()
                    if model.state == .loaded { await model.autoLogNaps(into: modelContext) }
                }
            }
            .sheet(item: $explaining) { metric in
                ExplanationSheet(metric: metric, value: value(for: metric), level: level(for: metric),
                                 todayNote: model.todayNote(for: metric))
            }
            .sheet(isPresented: $showingSleepDetail) {
                SleepDetailView(date: model.date)
            }
            .sheet(isPresented: $showingHeartDetail) {
                HeartRateDetailView(date: model.date)
            }
            .sheet(isPresented: $showingHistory) {
                NavigationStack { SleepHistoryView() }
            }
            .sheet(isPresented: $showingNaps) {
                NavigationStack { NapHistoryView() }
            }
            .sheet(isPresented: $showingNapInfo) {
                NapInfoSheet()
            }
            .sheet(isPresented: $showingProfile) { ProfileView() }
        }
    }

    // MARK: - Nội dung

    private var background: some View {
        ZStack(alignment: .top) {
            Theme.background
            LinearGradient(colors: [Theme.brand.opacity(0.14), Theme.brand.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 360)
        }
        .ignoresSafeArea()
    }

    /// "Chào buổi sáng,\nanh Minh" theo hồ sơ; hồ sơ trống thì chỉ lời chào.
    private var greetingLine: String {
        let p = profileSettings.profile
        guard !p.isEmpty else { return model.greeting }
        return "\(model.greeting),\n\(p.addressAs) \(p.displayName)"
    }

    /// Lần đầu cài (hồ sơ trống): mời điền hồ sơ để ngưỡng màu + lời khuyên đúng với mình.
    private var onboardingCard: some View {
        Button { showingProfile = true } label: {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: "person.text.rectangle.fill", tint: Theme.brand, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Điền hồ sơ của bạn")
                        .font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    Text("Tên, năm sinh, mục tiêu cân/ngủ/bước, bệnh nền và lời bác sĩ dặn — để màu xanh/vàng/đỏ và lời khuyên đúng với bạn.")
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.brand)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.dateText)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.brand)
            Text(greetingLine)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
            if model.state == .loaded {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                        .padding(.top, 2)
                    Text(model.summary)
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.brand.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .padding(.top, 8)
            }
        }
        .padding(.top, Theme.Space.l)
        .padding(.bottom, Theme.Space.xs)
    }

    private var content: some View {
        VStack(spacing: Theme.Space.l - 2) {
            SleepHeroCard(model: model, onExplain: { explaining = .sleep },
                          onOpenDetail: { showingSleepDetail = true })

            // T-032: AI đọc đêm qua → lời khuyên ngắn cho hôm nay (chỉ khi đã thiết lập AI + bật).
            MorningTipCard(date: model.date, ready: model.state == .loaded)

            HStack(alignment: .top, spacing: Theme.Space.m) {
                CompactMetricCard(metric: .restingHeartRate, value: model.heartValueText,
                                  level: model.heartLevel, caption: "Mức tốt ≤ 70 · chạm xem chi tiết",
                                  onExplain: { explaining = .restingHeartRate }) {
                    RangeBar(value: model.restingHeartRate, range: 50...100,
                             stops: [(70, Theme.good), (85, Theme.caution), (100, Theme.improve)])
                        .padding(.vertical, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture { showingHeartDetail = true }
                CompactMetricCard(metric: .steps, value: model.stepsValueText,
                                  level: model.stepsLevel, caption: stepsCaption,
                                  onExplain: { explaining = .steps }) {
                    ProgressBar(progress: model.stepsProgress, tint: Theme.steps).frame(height: 16)
                        .padding(.vertical, 2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)

            WeightCard(model: model) { explaining = .bodyMass }

            if model.showsGoogleMetrics && (model.hasHRV || model.hasSkinTemp) {
                googleMetricsRow
            }

            // T-020: nhịp thở, oxy máu, nhịp tim trong ngày, giờ vận động, quãng đường, calo.
            if model.hasVitals {
                VitalsCard(model: model,
                           onExplain: { explaining = $0 },
                           onOpenHeart: { showingHeartDetail = true })
            }

            NapCard(model: model,
                    onExplain: { showingNapInfo = true },
                    onOpen: { showingNaps = true })

            NextMealCard(date: model.date)
        }
    }

    /// Hai ô chỉ nguồn Google có: Biến thiên nhịp tim (HRV) và Nhiệt độ da.
    private var googleMetricsRow: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            if model.hasHRV {
                CompactMetricCard(metric: .heartRateVariability, value: model.hrvValueText,
                                  level: model.hrvLevel, caption: model.hrvCaption,
                                  onExplain: { explaining = .heartRateVariability }) {
                    RangeBar(value: model.hrv, range: 15...70,
                             stops: [(25, Theme.improve), (40, Theme.caution), (70, Theme.good)])
                        .padding(.vertical, 2)
                }
            }
            if model.hasSkinTemp {
                CompactMetricCard(metric: .skinTemperature, value: model.skinTempValueText,
                                  level: model.skinTempLevel, caption: model.skinTempCaption,
                                  onExplain: { explaining = .skinTemperature }) {
                    RangeBar(value: model.skinTemp.map { abs($0) }, range: 0...1.4,
                             stops: [(0.4, Theme.good), (0.9, Theme.caution), (1.4, Theme.improve)])
                        .padding(.vertical, 2)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var stepsCaption: String {
        let goal = Thresholds.stepsGoalText
        guard let s = model.steps else { return "Mục tiêu \(goal) bước" }
        let left = Thresholds.stepsGoal - s
        return left > 0 ? "Còn \(TodayViewModel.grouped(left)) tới \(goal)" : "Đã đạt \(goal) bước"
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nguồn: \(settings.source.title)", systemImage: settings.source.symbol)
                .foregroundStyle(Theme.brand)
            if let t = model.lastUpdated {
                Text("Cập nhật lúc \(TodayViewModel.time(t)). Kéo xuống để tải lại.")
            }
            if HealthStoreFactory.useMock {
                Label("Đang hiển thị số giả lập (máy ảo)", systemImage: "info.circle")
                    .foregroundStyle(Theme.caution)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.top, 4)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Đang đọc dữ liệu Sức khoẻ…")
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var authorizationView: some View {
        VStack(spacing: 20) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(Theme.heart)
            Text("BBHealth cần đọc giấc ngủ, nhịp tim, số bước và cân nặng từ ứng dụng Sức khoẻ để hiển thị bằng tiếng Việt.")
                .font(.title3)
                .multilineTextAlignment(.center)
            Button {
                Task { await model.requestAuthorization() }
            } label: {
                Text("Cho phép đọc dữ liệu Sức khoẻ")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.brand)
            .controlSize(.large)
            Text("Bạn có thể đổi lại bất cứ lúc nào trong Cài đặt → Sức khoẻ → Truy cập dữ liệu.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 40)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.caution)
            Text("Không đọc được dữ liệu")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Thử lại") { Task { await model.refresh() } }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .font(.title3)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Helpers

    private func value(for metric: Metric) -> String {
        switch metric {
        case .sleep: return model.sleepValueText
        case .restingHeartRate: return model.heartValueText
        case .steps: return model.stepsValueText
        case .bodyMass: return model.bodyMassValueText
        case .heartRateVariability: return model.hrvValueText
        case .skinTemperature: return model.skinTempValueText
        case .respiratoryRate: return model.respiratoryValueText
        case .oxygenSaturation: return model.oxygenValueText
        case .distance: return model.distanceValueText
        case .activeEnergy: return model.activeEnergyValueText
        case .activeHours: return model.activeHoursValueText
        case .heartRateRange: return model.heartRangeValueText
        case .liveHeartRate: return "—"   // chỉ dùng trong màn Nhịp tim trực tiếp
        }
    }

    private func level(for metric: Metric) -> MetricLevel {
        switch metric {
        case .sleep: return model.sleepLevel
        case .restingHeartRate: return model.heartLevel
        case .steps: return model.stepsLevel
        case .bodyMass: return model.bodyMassLevel
        case .heartRateVariability: return model.hrvLevel
        case .skinTemperature: return model.skinTempLevel
        case .respiratoryRate: return model.respiratoryLevel
        case .oxygenSaturation: return model.oxygenLevel
        case .distance: return model.distanceLevel
        case .activeEnergy: return model.activeEnergyLevel
        case .activeHours: return model.activeHoursLevel
        case .heartRateRange: return model.heartRangeLevel
        case .liveHeartRate: return .unknown
        }
    }
}

#Preview {
    TodayView()
}

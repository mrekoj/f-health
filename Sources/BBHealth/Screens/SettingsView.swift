import SwiftUI

/// Màn **Cài đặt**: chọn nguồn dữ liệu, đăng nhập/ngắt Google, xem trạng thái từng nguồn.
struct SettingsView: View {
    @State private var settings = AppSettings.shared
    @State private var auth = GoogleAuth.shared
    @State private var clientID: String = AppSettings.shared.googleClientID
    @State private var signingIn = false
    @State private var errorMessage: String?
    @State private var profileSettings = ProfileSettings.shared
    @State private var showingProfile = false
    @State private var ai = AISettings.shared
    @State private var showingAI = false
    @State private var weeklyReminder = WeeklyReminder.isEnabled

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Cài đặt")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, Theme.Space.l)

                    profileSection
                    aiSection
                    reminderSection
                    sourceSection
                    googleSection
                    appleSection
                    aboutFooter
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingProfile) { ProfileView() }
            .sheet(isPresented: $showingAI) { AISettingsView() }
            .task {
                if DebugOptions.showProfile { showingProfile = true }
                if DebugOptions.showAISettings { showingAI = true }
            }
            .alert("Chưa làm được", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Đóng", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Hồ sơ của tôi (T-025)

    private var profileSection: some View {
        let p = profileSettings.profile
        return Button { showingProfile = true } label: {
            HStack(spacing: 12) {
                IconBadge(symbol: "person.text.rectangle.fill", tint: Theme.brand, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hồ sơ của tôi").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    Text(p.displayName.isEmpty
                         ? "Chưa điền — chạm để nhập tuổi, mục tiêu, bệnh nền"
                         : "\(p.displayName) · \(p.age) tuổi · mục tiêu \(p.weightDirection.label.lowercased()) \(Thresholds.weightGoalText), ngủ \(Thresholds.sleepGoalText)")
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.brand)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Trợ lý AI (T-026: chọn hãng + dán khoá trong màn riêng)

    private var aiSection: some View {
        Button { showingAI = true } label: {
            HStack(spacing: 12) {
                IconBadge(symbol: "sparkles", tint: Theme.brand, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Trợ lý AI").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                        StatusChip(level: ai.isReady ? .good : .unknown, compact: true)
                    }
                    Text(ai.isReady
                         ? ai.summary
                         : (ai.kind == .none ? "Chưa bật — chạm để chọn Gemini (miễn phí), Claude hoặc OpenAI"
                                             : "\(ai.kind.title) — chưa có khoá, chạm để dán"))
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.brand)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Nhắc & xuất (T-033)

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Nhắc & xuất số liệu", symbol: "bell.badge.fill", tint: Theme.caution)
            Toggle("Nhắc báo cáo tuần — thứ Hai 7h30", isOn: Binding(
                get: { weeklyReminder },
                set: { on in
                    weeklyReminder = on
                    if on { Task { if await !WeeklyReminder.enable() { weeklyReminder = false; errorMessage = "Chưa được phép gửi thông báo. Bật trong Cài đặt máy → Thông báo → BBHealth." } } }
                    else { WeeklyReminder.disable() }
                }))
                .font(.callout).tint(Theme.brand)
            Text("Chạm thông báo là mở ngay Báo cáo tuần (AI tự phân tích nếu đã thiết lập). Mỗi ngày app cũng ghi 1 dòng vào health.csv — xem trong app Tệp → Trên iPhone của tôi → BBHealth.")
                .font(.footnote).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.caution)
    }

    // MARK: - Chọn nguồn

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Nguồn dữ liệu", symbol: "square.stack.3d.up.fill")
            Text("Chọn nơi app lấy chỉ số sức khoẻ để hiển thị ở màn Hôm nay và Xu hướng.")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 10) {
                ForEach(HealthSource.allCases) { source in
                    sourceRow(source)
                }
            }
        }
    }

    private func sourceRow(_ source: HealthSource) -> some View {
        let selected = settings.source == source
        return Button {
            settings.source = source
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: source.symbol, tint: selected ? Theme.brand : Theme.neutral)
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.title)
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text(source.subtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(selected ? Theme.brand : Theme.textTertiary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: selected ? Theme.brand : nil)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Google

    private var googleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Google Health", symbol: "g.circle.fill", tint: Theme.brand)

            statusRow(title: "Trạng thái",
                      value: auth.isConnected ? "Đã đăng nhập" : "Chưa đăng nhập",
                      level: auth.isConnected ? .good : .unknown)
            if let t = settings.lastUpdated(for: .google) {
                statusRow(title: "Cập nhật lần cuối", value: TodayViewModel.timeAndDate(t), level: nil)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Google OAuth Client ID")
                    .font(.label)
                    .foregroundStyle(Theme.textSecondary)
                TextField("NNN-xxxx.apps.googleusercontent.com", text: $clientID)
                    .font(.system(.callout, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
                    .onChange(of: clientID) { settings.googleClientID = clientID }
                Text("Mã OAuth lấy trong Google Cloud Console (Credentials → iOS client), dạng …apps.googleusercontent.com. KHÔNG phải khoá Gemini — khoá Gemini dán ở mục Trợ lý AI.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }

            if auth.isConnected {
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Label("Ngắt kết nối Google", systemImage: "xmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(Theme.improve)
                .controlSize(.large)
            } else {
                Button {
                    signIn()
                } label: {
                    HStack {
                        if signingIn { ProgressView().tint(.white) }
                        Text(signingIn ? "Đang mở Google…" : "Đăng nhập Google")
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .controlSize(.large)
                .disabled(signingIn || clientID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.brand)
    }

    private func signIn() {
        signingIn = true
        Task {
            do {
                try await auth.signIn(clientID: clientID)
            } catch {
                errorMessage = error.localizedDescription
            }
            signingIn = false
        }
    }

    // MARK: - Apple

    private var appleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Ứng dụng Sức khoẻ (Apple)", symbol: "heart.text.square.fill", tint: Theme.heart)
            statusRow(title: "Trạng thái", value: "Sẵn sàng trên máy này", level: .good)
            if let t = settings.lastUpdated(for: .apple) {
                statusRow(title: "Cập nhật lần cuối", value: TodayViewModel.timeAndDate(t), level: nil)
            }
            Text("Đổi quyền đọc trong Cài đặt (máy) → Sức khoẻ → Truy cập & Thiết bị → BBHealth.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart)
    }

    private func statusRow(title: String, value: String, level: MetricLevel?) -> some View {
        HStack {
            Text(title)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if let level {
                StatusChip(level: level, compact: true)
            }
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var aboutFooter: some View {
        Text("BBHealth — không tài khoản, không máy chủ; dữ liệu và hồ sơ ở ngay trên máy. Chỉ rời máy khi anh chủ động sao chép/chia sẻ hoặc nhờ AI.")
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)
            .padding(.top, 4)
    }
}

#Preview {
    SettingsView()
}

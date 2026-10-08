import SwiftUI

/// Trạng thái onboarding (lần đầu mở app / hồ sơ trống). Lưu cờ đã-xong trong UserDefaults.
enum OnboardingState {
    private static let key = "bbh.onboarded.v1"
    static var done: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Có hiện màn chào mừng không: chưa onboard xong **và** hồ sơ còn trống.
    static var shouldShow: Bool {
        #if DEBUG
        if DebugOptions.showOnboarding { return true }
        #endif
        return !done && HealthProfileStore.current.isEmpty
    }
}

/// Màn **Chào mừng** cho người mới (T-034): 4 bước ngắn, tiếng Việt —
/// (1) app làm gì + dữ liệu chỉ ở trên máy · (2) tên/xưng hô/năm sinh/giới/cao ·
/// (3) mục tiêu cân/ngủ/bước · (4) nguồn dữ liệu + xin quyền. Mỗi bước bỏ qua được.
struct OnboardingView: View {
    /// Gọi khi đóng (dù xong hay bỏ qua) — RootTabView tắt fullScreenCover.
    var onFinish: () -> Void

    @State private var step = 0
    @State private var draft = HealthProfile.blank
    @State private var chosenSource: HealthSource?
    @State private var requesting = false

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    switch step {
                    case 0: welcomeStep
                    case 1: basicsStep
                    case 2: goalsStep
                    default: sourceStep
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.l)
                .padding(.bottom, Theme.Space.xxl)
            }
            footer
        }
        .background(Theme.background.ignoresSafeArea())
    }

    // MARK: - Khung

    private var header: some View {
        HStack {
            // Chấm tiến độ 4 bước.
            HStack(spacing: 6) {
                ForEach(0...lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Theme.brand : Theme.surfaceMuted)
                        .frame(width: i == step ? 22 : 8, height: 8)
                }
            }
            Spacer()
            Button("Bỏ qua, điền sau") { finish(saveProfile: false) }
                .font(.callout).foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, Theme.Space.l)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if step > 0 {
                Button { withAnimation { step -= 1 } } label: {
                    Label("Quay lại", systemImage: "chevron.left").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.brand)
            }
            Button {
                if step < lastStep { withAnimation { step += 1 } } else { finishWithSource() }
            } label: {
                Group {
                    if requesting { ProgressView().tint(.white) }
                    else { Text(step < lastStep ? "Tiếp tục" : "Xong").frame(maxWidth: .infinity) }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).tint(Theme.brand)
            .disabled(requesting)
        }
        .controlSize(.large)
        .padding(.horizontal, Theme.Space.page)
        .padding(.vertical, Theme.Space.m)
        .background(.ultraThinMaterial)
    }

    // MARK: - Bước 1: chào + app làm gì + riêng tư

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            IconBadge(symbol: "heart.text.square.fill", tint: Theme.brand, size: 56)
            Text("Chào mừng bạn đến BBHealth")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text("App đọc giấc ngủ, nhịp tim, số bước và cân nặng từ ứng dụng Sức khoẻ của bạn (hoặc Google Health), rồi hiển thị bằng tiếng Việt dễ hiểu theo mục tiêu riêng của bạn, kèm giải thích và gợi ý.")
                .font(.body).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            infoRow("lock.fill", Theme.good, "Dữ liệu chỉ nằm trên máy bạn",
                    "Không có máy chủ, không tài khoản. Số liệu chỉ rời máy khi bạn chủ động chia sẻ báo cáo hoặc nhờ AI phân tích.")
            infoRow("paintpalette.fill", Theme.caution, "Màu xanh/vàng/đỏ theo bạn",
                    "Hãy điền vài thông tin để app tô màu và khuyên đúng với mình. Bỏ qua cũng được, điền sau trong Cài đặt → Hồ sơ.")
        }
    }

    // MARK: - Bước 2: thông tin cơ bản

    private var basicsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Vài thông tin về bạn", "Để xưng hô đúng và tính ngưỡng nhịp tim theo tuổi.")
            card {
                row("Tên gọi") {
                    TextField("Tên của bạn", text: $draft.displayName).multilineTextAlignment(.trailing)
                }
                row("Xưng hô") {
                    Picker("Xưng hô", selection: $draft.addressAs) {
                        ForEach(["anh", "chị", "em", "bạn", "cô", "chú", "bác"], id: \.self) { Text($0).tag($0) }
                    }.pickerStyle(.menu)
                }
                row("Năm sinh") {
                    TextField("1990", value: $draft.birthYear, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
                row("Giới") {
                    Picker("Giới", selection: $draft.sex) {
                        ForEach(ProfileSex.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).frame(maxWidth: 200)
                }
                row("Chiều cao (cm)") {
                    TextField("170", value: $draft.heightCm, format: .number.precision(.fractionLength(0)))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }
        }
    }

    // MARK: - Bước 3: mục tiêu

    private var goalsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle("Mục tiêu của bạn", "Quyết định màu xanh/vàng/đỏ của các ô trong app.")
            card {
                row("Cân nặng") {
                    Picker("Hướng", selection: $draft.weightDirection) {
                        ForEach(WeightGoalDirection.allCases) { Text($0.label).tag($0) }
                    }.pickerStyle(.menu)
                }
                row("Cân mục tiêu (kg)") {
                    TextField("60", value: $draft.weightGoalKg, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                row("Ngủ mỗi đêm (giờ)") {
                    TextField("7", value: $draft.sleepGoalHours, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                }
                row("Bước mỗi ngày") {
                    TextField("6000", value: $draft.stepsGoal, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing)
                }
            }
            Text("Bệnh nền, lời bác sĩ dặn, thuốc… bạn điền thêm sau trong Cài đặt → Hồ sơ của tôi để app và trợ lý AI hiểu đúng mình.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bước 4: nguồn dữ liệu

    private var sourceStep: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            stepTitle("Lấy dữ liệu từ đâu?", "Chọn nơi app đọc số liệu sức khoẻ. Đổi lại bất cứ lúc nào trong Cài đặt.")
            sourceOption(.apple, "heart.fill", "Apple Health (HealthKit)",
                         "Dữ liệu đã đồng bộ về ứng dụng Sức khoẻ của iPhone. App sẽ xin quyền đọc.")
            sourceOption(.google, "globe", "Google Health",
                         "Đọc thẳng từ máy chủ Google. Cần dán Client ID + đăng nhập trong Cài đặt.")
            sourceOption(nil, "clock.arrow.circlepath", "Bỏ qua, chọn sau",
                         "Vào app trước, chọn nguồn trong Cài đặt khi sẵn sàng.")
        }
    }

    private func sourceOption(_ src: HealthSource?, _ symbol: String, _ title: String, _ desc: String) -> some View {
        Button { chosenSource = src } label: {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: symbol, tint: Theme.brand, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    Text(desc).font(.callout).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: chosenSource == src ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(chosenSource == src ? Theme.brand : Theme.textTertiary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: chosenSource == src ? Theme.brand : nil)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Mảnh dùng chung

    private func stepTitle(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(Theme.textPrimary)
            Text(sub).font(.callout).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { content() }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
            content()
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func infoRow(_ symbol: String, _ tint: Color, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.cardTitle).foregroundStyle(Theme.textPrimary)
                Text(desc).font(.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint)
    }

    // MARK: - Kết thúc

    /// Bước cuối: áp nguồn đã chọn + xin quyền (nếu Apple) rồi đóng.
    private func finishWithSource() {
        guard let src = chosenSource else { finish(saveProfile: true); return }
        AppSettings.shared.source = src
        if src == .google {
            finish(saveProfile: true)   // Google cần đăng nhập OAuth trong Cài đặt — không chặn onboarding.
            return
        }
        requesting = true
        Task { @MainActor in
            try? await HealthStoreFactory.make(for: src).requestAuthorization()
            requesting = false
            finish(saveProfile: true)
        }
    }

    /// Lưu hồ sơ (nếu có điền) + đánh dấu đã onboard, rồi gọi onFinish.
    private func finish(saveProfile: Bool) {
        if saveProfile && !draft.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            ProfileSettings.shared.profile = draft
        }
        OnboardingState.done = true
        onFinish()
    }
}

#Preview {
    OnboardingView(onFinish: {})
}

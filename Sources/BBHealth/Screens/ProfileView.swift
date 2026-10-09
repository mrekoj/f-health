import SwiftUI
import UniformTypeIdentifiers

/// Màn **Hồ sơ của tôi** (T-025): tuổi, mục tiêu, bệnh nền, BS dặn… — vừa chỉnh ngưỡng màu trong app,
/// vừa là phần "Hồ sơ" gửi kèm cho AI. Mặc định trống (hoặc nạp từ Resources/Private/OwnerProfile.json).
struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var settings = ProfileSettings.shared
    @State private var confirmReset = false
    @State private var confirmClear = false
    @State private var showingWhy = false
    @State private var showingImporter = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    intro
                    basicsCard
                    goalsCard
                    textCard("Bệnh nền / tình trạng", symbol: "cross.case.fill", tint: Theme.heart,
                             hint: "Mỗi dòng một bệnh hoặc tình trạng đang theo dõi.", text: $settings.profile.conditions)
                    textCard("Bác sĩ dặn", symbol: "stethoscope", tint: Theme.improve,
                             hint: "Những điều bắt buộc theo — app và AI sẽ bám theo đây.", text: $settings.profile.doctorNotes)
                    textCard("Ăn uống", symbol: "fork.knife", tint: Theme.meal,
                             hint: "Kiêng gì, ăn thế nào, mấy bữa.", text: $settings.profile.dietNotes)
                    textCard("Thuốc / bổ sung", symbol: "pills.fill", tint: Theme.hrv,
                             hint: "Đang dùng gì, liều, từ khi nào.", text: $settings.profile.medications)
                    textCard("Lối sống", symbol: "figure.walk", tint: Theme.steps,
                             hint: "Công việc, rượu bia, tập luyện, giờ giấc.", text: $settings.profile.lifestyleNotes)
                    resetButtons
                    Text("Hồ sơ lưu ngay trên máy. Chỉ rời máy khi anh bấm Sao chép/Chia sẻ báo cáo hoặc nhờ AI phân tích.")
                        .font(.footnote).foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Hồ sơ của tôi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Xong") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingWhy = true } label: { Image(systemName: "questionmark.circle") }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .alert("Về hồ sơ mặc định?", isPresented: $confirmReset) {
                Button("Về mặc định", role: .destructive) { settings.restoreOwner() }
                Button("Thôi", role: .cancel) {}
            } message: { Text("Thay toàn bộ bằng hồ sơ mặc định (file riêng OwnerProfile.json nếu có, không thì trống).") }
            .alert("Xoá trắng hồ sơ?", isPresented: $confirmClear) {
                Button("Xoá trắng", role: .destructive) { settings.clear() }
                Button("Thôi", role: .cancel) {}
            } message: { Text("Dành cho người dùng mới tự điền hồ sơ của mình.") }
            .sheet(isPresented: $showingWhy) { whySheet }
            .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
                importProfile(from: result)
            }
            .alert("Nhập hồ sơ", isPresented: Binding(get: { importMessage != nil },
                                                      set: { if !$0 { importMessage = nil } })) {
                Button("Xong", role: .cancel) {}
            } message: { Text(importMessage ?? "") }
        }
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: "person.text.rectangle.fill", tint: Theme.brand, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("Để app và trợ lý AI hiểu đúng bạn")
                    .font(.cardTitle).foregroundStyle(Theme.textPrimary)
                Text("Mục tiêu ở đây quyết định màu xanh/vàng/đỏ của các ô. Bệnh nền, lời BS dặn sẽ đi kèm báo cáo khi bạn nhờ AI phân tích.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.brand)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Thông tin cơ bản

    private var basicsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Thông tin cơ bản", symbol: "person.fill")
            fieldRow("Tên gọi") {
                TextField("Tên của bạn", text: $settings.profile.displayName)
                    .multilineTextAlignment(.trailing)
            }
            fieldRow("Xưng hô") {
                Picker("Xưng hô", selection: $settings.profile.addressAs) {
                    ForEach(["anh", "chị", "em", "bạn", "cô", "chú", "bác"], id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.menu)
            }
            fieldRow("Năm sinh") {
                TextField("1990", value: $settings.profile.birthYear, format: .number.grouping(.never))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            fieldRow("Giới") {
                Picker("Giới", selection: $settings.profile.sex) {
                    ForEach(ProfileSex.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).frame(maxWidth: 200)
            }
            fieldRow("Chiều cao (cm)") {
                TextField("170", value: $settings.profile.heightCm, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Mục tiêu

    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Mục tiêu (quyết định màu ngưỡng)", symbol: "target", tint: Theme.good)
            fieldRow("Cân nặng") {
                Picker("Hướng", selection: $settings.profile.weightDirection) {
                    ForEach(WeightGoalDirection.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
            }
            fieldRow("Cân mục tiêu (kg)") {
                TextField("53", value: $settings.profile.weightGoalKg, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            fieldRow("Ngủ mỗi đêm (giờ)") {
                TextField("7", value: $settings.profile.sleepGoalHours, format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
            }
            fieldRow("Bước mỗi ngày") {
                TextField("6000", value: $settings.profile.stepsGoal, format: .number.grouping(.never))
                    .keyboardType(.numberPad).multilineTextAlignment(.trailing)
            }
            Text("Ngưỡng hiện tại: ngủ \(Thresholds.bands(for: .sleep).map { "\($0.level.label) \($0.range)" }.joined(separator: " · ")); cân \(Thresholds.bands(for: .bodyMass).map(\.range).joined(separator: " · ")).")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.good)
    }

    private func fieldRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
            content()
                .font(.system(.body, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Ô văn bản dài

    private func textCard(_ title: String, symbol: String, tint: Color, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title, symbol: symbol, tint: tint)
            Text(hint).font(.footnote).foregroundStyle(Theme.textTertiary)
            TextEditor(text: text)
                .font(.callout)
                .foregroundStyle(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(8)
                .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint)
    }

    private var resetButtons: some View {
        VStack(spacing: 10) {
            Button { showingImporter = true } label: {
                Label("Nhập hồ sơ từ tệp JSON", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(Theme.good)
            HStack(spacing: 10) {
                Button { confirmReset = true } label: {
                    Label("Về mặc định", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.brand)
                Button { confirmClear = true } label: {
                    Label("Xoá trắng", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(Theme.improve)
            }
            Text("Nhập từ JSON: chọn tệp hồ sơ đã lưu (ví dụ OwnerProfile.json) để khôi phục nhanh toàn bộ hồ sơ của bạn.")
                .font(.footnote).foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        .controlSize(.large)
    }

    /// Nạp hồ sơ từ tệp JSON người dùng chọn (đúng định dạng HealthProfile; ngày kiểu ISO-8601 hoặc số).
    private func importProfile(from result: Result<URL, Error>) {
        switch result {
        case .failure(let e):
            importMessage = "Không mở được tệp: \(e.localizedDescription)"
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                importMessage = "Không đọc được nội dung tệp."
                return
            }
            let iso = JSONDecoder(); iso.dateDecodingStrategy = .iso8601
            if let p = try? iso.decode(HealthProfile.self, from: data) {
                settings.profile = p
                importMessage = "Đã nhập hồ sơ của \(p.displayName.isEmpty ? "bạn" : p.displayName)."
            } else if let p = try? JSONDecoder().decode(HealthProfile.self, from: data) {
                settings.profile = p
                importMessage = "Đã nhập hồ sơ của \(p.displayName.isEmpty ? "bạn" : p.displayName)."
            } else {
                importMessage = "Tệp không đúng định dạng hồ sơ. Hãy chọn tệp JSON xuất từ app (OwnerProfile.json)."
            }
        }
    }

    private var whySheet: some View {
        InfoSheet(
            title: "Hồ sơ dùng để làm gì?",
            symbol: "person.text.rectangle.fill",
            tint: Theme.brand,
            sections: [
                .init(title: "Ngưỡng màu theo anh", symbol: "paintpalette.fill", tint: Theme.good,
                      text: "App tô màu các ô theo mục tiêu riêng của bạn (ngủ, bước, cân) chứ không theo chuẩn chung. Đổi mục tiêu ở đây là màu đổi theo ngay."),
                .init(title: "Gửi kèm cho AI", symbol: "sparkles", tint: Theme.brand,
                      text: "Khi anh nhờ AI phân tích, phần hồ sơ (bệnh nền, lời BS dặn, kiêng khem, thuốc) đi kèm số liệu để AI khuyên đúng người, đúng bệnh — thay vì lời khuyên chung chung."),
                .init(title: "Gợi ý", symbol: "lightbulb.fill", tint: Theme.caution,
                      text: "Chỉ ghi những gì anh muốn AI biết. Hồ sơ nằm trên máy; muốn đưa máy cho người khác dùng thì bấm Xoá trắng để họ tự điền."),
            ])
    }
}

#Preview {
    ProfileView()
}

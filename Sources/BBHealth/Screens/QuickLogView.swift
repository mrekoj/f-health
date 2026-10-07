import SwiftUI
import SwiftData

/// Màn **Ghi nhanh**: ghi bữa ăn, rượu bia, triệu chứng, cân nặng trong ≤ 3 chạm.
/// Lưu bằng SwiftData (DailyLog/LogEntry); cân nặng ghi thêm vào HealthKit qua `saveBodyMass`.
struct QuickLogView: View {
    @Environment(\.modelContext) private var context
    @Query private var entries: [LogEntry]

    @State private var selectedMealID: String
    @State private var lyCount = 0
    @State private var alcoholTime: Date
    @State private var selectedSymptoms: Set<String> = []
    @State private var weightText = ""
    @State private var savingWeight = false
    @State private var toastText: String?
    @FocusState private var weightFocused: Bool

    private let provider = HealthStoreFactory.make()
    private let today = DebugOptions.now

    init() {
        let start = Calendar.current.startOfDay(for: DebugOptions.now)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        _entries = Query(filter: #Predicate<LogEntry> { $0.timestamp >= start && $0.timestamp < end },
                         sort: \.timestamp, order: .reverse)
        _selectedMealID = State(initialValue: MealPlan.nextMeal(at: DebugOptions.now).meal.id)
        _alcoholTime = State(initialValue: DebugOptions.now)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    headerCard.clearRow()
                    mealCard.clearRow()
                    alcoholCard.clearRow()
                    symptomCard.clearRow()
                    weightCard.clearRow()

                    entriesHeader.clearRow()
                    if entries.isEmpty {
                        emptyRow.clearRow()
                    } else {
                        ForEach(entries) { entry in
                            LogEntryRow(entry: entry).clearRow(v: 4)
                        }
                        .onDelete(perform: delete)
                    }
                    Color.clear.frame(height: 1).id("logBottom").clearRow(v: 0)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .background(Theme.background.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Xong") { weightFocused = false }
                    }
                }
                .overlay(alignment: .bottom) { toastView }
                .onAppear {
                    seedIfNeeded()
                    if DebugOptions.scrollToBottom {
                        Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            withAnimation { proxy.scrollTo("logBottom", anchor: .bottom) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tiêu đề

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Ghi nhanh")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(dateText)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Bữa ăn

    private var mealCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(.meal, subtitle: "Chọn bữa rồi chạm món để ghi")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(MealPlan.officeDay) { mealChip($0) }
                }
                .padding(.horizontal, 1)
            }
            VStack(spacing: 8) {
                ForEach(Array(selectedMeal.options.enumerated()), id: \.offset) { _, option in
                    optionButton(selectedMeal, option)
                }
            }
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.meal)
    }

    private var selectedMeal: Meal {
        MealPlan.officeDay.first { $0.id == selectedMealID } ?? MealPlan.officeDay[0]
    }

    private func mealChip(_ meal: Meal) -> some View {
        let selected = meal.id == selectedMealID
        return Button {
            selectedMealID = meal.id
        } label: {
            VStack(spacing: 3) {
                Image(systemName: meal.symbol).font(.system(size: 16, weight: .semibold))
                Text(meal.name).font(.system(.caption, design: .rounded).weight(.semibold)).lineLimit(1)
                Text(meal.time).font(.system(.caption2, design: .rounded))
            }
            .foregroundStyle(selected ? .white : Theme.meal)
            .frame(width: 86)
            .padding(.vertical, 10)
            .background(selected ? Theme.meal : Theme.meal.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func optionButton(_ meal: Meal, _ option: String) -> some View {
        Button {
            logMeal(meal, option: option)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.meal)
                Text(option)
                    .font(.callout)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rượu bia

    private var alcoholCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(.alcohol, subtitle: "Nên kiêng — ghi lại nếu có uống")
            Stepper(value: $lyCount, in: 0...20) {
                HStack(spacing: 10) {
                    Text("Số ly").font(.label).foregroundStyle(Theme.textSecondary)
                    Text("\(lyCount)")
                        .font(.number(24, weight: .bold)).monospacedDigit()
                        .foregroundStyle(lyCount == 0 ? Theme.textTertiary : Theme.improve)
                }
            }
            HStack {
                Label("Giờ uống", systemImage: "clock")
                    .font(.label).foregroundStyle(Theme.textSecondary)
                Spacer()
                DatePicker("", selection: $alcoholTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            logButton("Ghi rượu bia", tint: Theme.improve, disabled: lyCount == 0, action: logAlcohol)
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.improve)
    }

    // MARK: - Triệu chứng

    private var symptomCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(.symptom, subtitle: "Chọn nhiều dấu hiệu nếu có")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(Symptom.all, id: \.self) { symptomChip($0) }
            }
            logButton("Ghi triệu chứng", tint: Theme.caution,
                      disabled: selectedSymptoms.isEmpty, action: logSymptoms)
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.caution)
    }

    private func symptomChip(_ name: String) -> some View {
        let on = selectedSymptoms.contains(name)
        return Button {
            if on { selectedSymptoms.remove(name) } else { selectedSymptoms.insert(name) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.footnote)
                Text(name).font(.system(.subheadline, design: .rounded).weight(.medium)).lineLimit(1)
            }
            .foregroundStyle(on ? .white : Theme.caution)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(on ? Theme.caution : Theme.caution.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cân nặng

    private var weightCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(.weight, subtitle: "Nhập cân, lưu vào ứng dụng Sức khoẻ")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("48,5", text: $weightText)
                    .keyboardType(.decimalPad)
                    .focused($weightFocused)
                    .font(.number(32)).monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("kg")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.75),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            logButton(savingWeight ? "Đang lưu…" : "Lưu cân nặng", tint: Theme.weight,
                      disabled: parsedWeight == nil || savingWeight, action: logWeight)
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.weight)
    }

    private var parsedWeight: Double? {
        let s = weightText.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let kg = Double(s), kg > 20, kg < 200 else { return nil }
        return kg
    }

    // MARK: - Danh sách hôm nay

    private var entriesHeader: some View {
        SectionHeader(title: "Hôm nay đã ghi", symbol: "checklist",
                      trailing: entries.isEmpty ? nil : "\(entries.count) mục")
            .padding(.top, Theme.Space.s)
    }

    private var emptyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray").font(.title3).foregroundStyle(Theme.textTertiary)
            Text("Chưa ghi gì hôm nay. Chọn bữa ăn, số ly, triệu chứng hoặc nhập cân ở trên.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
    }

    // MARK: - Thành phần chung

    private func cardHeader(_ kind: LogKind, subtitle: String? = nil) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: kind.symbol, tint: kind.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.label).font(.cardTitle).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func logButton(_ title: String, tint: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(disabled ? AnyShapeStyle(Theme.neutral.opacity(0.35)) : AnyShapeStyle(tint),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    @ViewBuilder private var toastView: some View {
        if let toastText {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                Text(toastText).font(.system(.subheadline, design: .rounded).weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Theme.brandDeep, in: Capsule())
            .shadow(color: Theme.shadow, radius: 12, y: 4)
            .padding(.bottom, 14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEE, d 'tháng' M"
        let s = f.string(from: today)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    // MARK: - Ghi & xoá

    private func logMeal(_ meal: Meal, option: String) {
        add(LogEntry(kind: .meal, title: meal.name, detail: option, timestamp: today))
        toast("Đã ghi \(meal.name)")
    }

    private func logAlcohol() {
        guard lyCount > 0 else { return }
        add(LogEntry(kind: .alcohol, title: "Rượu bia", detail: "\(lyCount) ly",
                     amount: Double(lyCount), timestamp: alcoholTime))
        toast("Đã ghi \(lyCount) ly rượu bia")
        lyCount = 0
    }

    private func logSymptoms() {
        guard !selectedSymptoms.isEmpty else { return }
        let list = Symptom.all.filter { selectedSymptoms.contains($0) }
        add(LogEntry(kind: .symptom, title: "Triệu chứng",
                     detail: list.joined(separator: ", "), timestamp: today))
        toast("Đã ghi triệu chứng")
        selectedSymptoms = []
    }

    private func logWeight() {
        guard let kg = parsedWeight else { return }
        weightFocused = false
        savingWeight = true
        let text = TodayViewModel.decimal(kg, digits: 1)
        Task {
            do {
                try await provider.saveBodyMass(kg: kg, date: today)
                add(LogEntry(kind: .weight, title: "Cân nặng", detail: "\(text) kg", amount: kg, timestamp: today))
                weightText = ""
                toast("Đã lưu \(text) kg vào Sức khoẻ")
            } catch {
                toast("Lưu cân thất bại")
            }
            savingWeight = false
        }
    }

    private func add(_ entry: LogEntry) {
        LogEntry.add(entry, on: entry.timestamp, in: context)
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets { context.delete(entries[i]) }
    }

    private func toast(_ text: String) {
        withAnimation(.spring(duration: 0.3)) { toastText = text }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut) { toastText = nil }
        }
    }

    private func seedIfNeeded() {
        guard DebugOptions.seedLog, entries.isEmpty else { return }
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: today) ?? today }
        add(LogEntry(kind: .meal, title: "Bữa sáng", detail: "Phở gà (không chanh, tương ớt)", timestamp: at(7, 10)))
        add(LogEntry(kind: .weight, title: "Cân nặng", detail: "48,5 kg", amount: 48.5, timestamp: at(7, 20)))
        add(LogEntry(kind: .symptom, title: "Triệu chứng", detail: "Đầy bụng, Ợ nóng", timestamp: at(9, 40)))
        add(LogEntry(kind: .meal, title: "Phụ sáng", detail: "Sữa chua ít đường, không chua + granola", timestamp: at(9, 45)))
        // Vài ngày trước — để màn Báo cáo tuần (T-025) có rượu bia/triệu chứng mà đối chiếu.
        func ago(_ days: Int, _ h: Int, _ m: Int) -> Date {
            let d = cal.date(byAdding: .day, value: -days, to: today) ?? today
            return cal.date(bySettingHour: h, minute: m, second: 0, of: d) ?? d
        }
        func addPast(_ e: LogEntry, _ days: Int) { LogEntry.add(e, on: ago(days, 12, 0), in: context) }
        addPast(LogEntry(kind: .alcohol, title: "Rượu bia", detail: "3 ly", amount: 3, timestamp: ago(2, 20, 30)), 2)
        addPast(LogEntry(kind: .symptom, title: "Triệu chứng", detail: "Đầy bụng, Mất ngủ", timestamp: ago(1, 8, 15)), 1)
        addPast(LogEntry(kind: .alcohol, title: "Rượu bia", detail: "2 ly", amount: 2, timestamp: ago(5, 19, 40)), 5)
        addPast(LogEntry(kind: .meal, title: "Bữa tối", detail: "Cháo cá", timestamp: ago(3, 18, 50)), 3)
        addPast(LogEntry(kind: .weight, title: "Cân nặng", detail: "48,2 kg", amount: 48.2, timestamp: ago(6, 7, 15)), 6)
    }
}

// MARK: - Dòng một mục đã ghi

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: entry.kind.symbol, tint: entry.kind.tint, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let d = entry.detail {
                    Text(d).font(.footnote).foregroundStyle(Theme.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(TodayViewModel.time(entry.timestamp))
                .font(.system(.footnote, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.textTertiary).monospacedDigit()
        }
        .padding(12)
        .card(tint: entry.kind.tint, radius: Theme.Radius.small)
    }
}

// MARK: - Dòng List nền trong suốt

private extension View {
    func clearRow(v: CGFloat = 6) -> some View {
        self
            .listRowInsets(EdgeInsets(top: v, leading: Theme.Space.page, bottom: v, trailing: Theme.Space.page))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

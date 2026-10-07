import SwiftUI

/// Màn **Lịch sử giấc ngủ**: danh sách nhiều đêm gần đây; chạm 1 đêm để mở chi tiết.
/// Được đẩy vào từ màn Giấc ngủ chi tiết (nút "Xem các đêm khác").
struct SleepHistoryView: View {
    @State private var model: SleepHistoryViewModel
    @State private var settings = AppSettings.shared
    @State private var night: NightRef?
    @State private var showExplain = false

    struct NightRef: Identifiable { let date: Date; var id: Date { date } }

    init(today: Date = DebugOptions.now) {
        _model = State(initialValue: SleepHistoryViewModel(today: today))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                rangePicker
                switch model.state {
                case .idle, .loading:
                    ProgressView().controlSize(.large)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                case .empty:
                    emptyView
                case .failed(let m):
                    Text(m).font(.callout).foregroundStyle(Theme.improve)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                case .loaded:
                    summaryCard
                    nightsCard
                }
            }
            .padding(.horizontal, Theme.Space.page)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Lịch sử giấc ngủ")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpButton(title: "Giấc ngủ") { showExplain = true }
            }
        }
        .task { await model.load() }
        .onChange(of: model.nightCount) { Task { await model.reload() } }
        .onChange(of: settings.source) { Task { await model.reload() } }
        .sheet(item: $night) { SleepDetailView(date: $0.date) }
        .sheet(isPresented: $showExplain) {
            ExplanationSheet(metric: .sleep, value: explainValue,
                             level: Thresholds.sleep(hours: model.avgHours), todayNote: explainNote)
        }
    }

    // MARK: - Chọn số đêm

    private var rangePicker: some View {
        Picker("Số đêm", selection: $model.nightCount) {
            Text("14 đêm").tag(14)
            Text("30 đêm").tag(30)
        }
        .pickerStyle(.segmented)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Tóm tắt

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: Theme.Space.m) {
                tile("Ngủ đủ 7h", value: "\(model.goodNights)", unit: "/\(model.nights.count) đêm")
                if let a = model.avgHours {
                    tile("Ngủ trung bình", value: TodayViewModel.decimal(a, digits: 1), unit: "giờ/đêm")
                }
            }
            Text("Màu theo ngưỡng của bạn: xanh = ngủ đủ 7 giờ, vàng = 6–7 giờ, đỏ = dưới 6 giờ.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.sleep)
    }

    private func tile(_ title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Text(value).font(.number(24)).foregroundStyle(Theme.textPrimary)
            Text(unit).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.sleep.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }

    // MARK: - Danh sách đêm

    private var nightsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.nights.enumerated()), id: \.element.id) { idx, n in
                Button { night = NightRef(date: n.date) } label: { nightRow(n) }
                    .buttonStyle(.plain)
                if idx < model.nights.count - 1 {
                    Divider().padding(.leading, Theme.Space.l)
                }
            }
        }
        .card()
    }

    private func nightRow(_ n: SleepNight) -> some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(weekday(n.date)).font(.caption).foregroundStyle(Theme.textSecondary)
                Text(dayMonth(n.date)).font(.number(17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            }
            .frame(width: 58, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(TodayViewModel.decimal(n.hours, digits: 1))
                        .font(.number(24)).foregroundStyle(n.level.color)
                    Text("giờ ngủ").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Text(subtitle(n))
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, Theme.Space.l)
        .contentShape(Rectangle())
    }

    private func subtitle(_ n: SleepNight) -> String {
        var parts: [String] = []
        if let b = n.summary.bedTime, let w = n.summary.wakeTime {
            parts.append("\(TodayViewModel.time(b)) → \(TodayViewModel.time(w))")
        }
        parts.append(n.summary.awakeCount == 0 ? "không thức giấc" : "thức \(n.summary.awakeCount) lần")
        return parts.joined(separator: " · ")
    }

    // MARK: - Trạng thái trống

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bed.double").font(.system(size: 54)).foregroundStyle(Theme.sleep)
            Text("Chưa có dữ liệu giấc ngủ cho các đêm gần đây.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }

    // MARK: - Sheet giải thích

    private var explainValue: String {
        model.avgHours.map { TodayViewModel.decimal($0, digits: 1) } ?? "—"
    }
    private var explainNote: String {
        guard let a = model.avgHours else { return "Chưa có đủ dữ liệu giấc ngủ gần đây." }
        return "Trung bình \(model.nights.count) đêm gần đây anh ngủ \(TodayViewModel.decimal(a, digits: 1)) giờ mỗi đêm, trong đó có \(model.goodNights) đêm ngủ đủ 7 giờ."
    }

    // MARK: - Định dạng ngày

    private func weekday(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EEE"
        return f.string(from: d).capitalized
    }
    private func dayMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
        return f.string(from: d)
    }
}

import SwiftUI
import SwiftData
import Charts

/// Màn **Xu hướng**: 7/30 ngày — giấc ngủ, nhịp tim nghỉ, bước, cân; đánh dấu ngày có rượu bia.
struct TrendsView: View {
    @State private var model = TrendsViewModel(today: DebugOptions.now, range: DebugOptions.trendsRange)
    @State private var settings = AppSettings.shared
    @State private var selectedSleepDate: Date?
    @State private var night: NightRef?
    /// Màn Báo cáo (T-025) mở từ nút trên tiêu đề.
    @State private var reportKind: ReportKind?
    @State private var pending = PendingNavigation.shared

    struct NightRef: Identifiable { let date: Date; var id: Date { date } }

    /// Các mục rượu bia để đánh dấu ngày tương quan.
    @Query(filter: #Predicate<LogEntry> { $0.kindRaw == "alcohol" })
    private var alcoholEntries: [LogEntry]

    private var alcoholDays: Set<Date> {
        Set(alcoholEntries.filter { ($0.amount ?? 0) > 0 }
            .map { Calendar.current.startOfDay(for: $0.timestamp) })
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header
                    rangePicker
                    switch model.state {
                    case .idle, .loading:
                        ProgressView().controlSize(.large)
                            .frame(maxWidth: .infinity).padding(.top, 60)
                    case .failed(let m):
                        Text(m).font(.callout).foregroundStyle(Theme.improve)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    case .loaded:
                        summaryCard
                        sleepChartCard
                        rhrChartCard
                        stepsChartCard
                        if !model.activeHours.isEmpty { activeHoursChartCard }
                        if !model.distance.isEmpty { distanceChartCard }
                        weightChartCard
                        if settings.source.usesGoogle && !model.hrv.isEmpty { hrvChartCard }
                        if settings.source.usesGoogle && !model.skinTemp.isEmpty { skinTempChartCard }
                        if !alcoholDays.isEmpty { legend }
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if model.state == .idle { await model.load() }
                if let k = DebugOptions.showReport { reportKind = k }
            }
            .onChange(of: model.range) { Task { await model.load() } }
            .onChange(of: settings.source) { Task { await model.load() } }
            .sheet(item: $night) { SleepDetailView(date: $0.date) }
            .sheet(item: $reportKind) { ReportView(kind: $0) }
            .onChange(of: pending.openWeeklyReport, initial: true) {
                if pending.openWeeklyReport { pending.openWeeklyReport = false; reportKind = .week }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Xu hướng")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Nhìn lại \(model.range) ngày gần nhất")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            // Báo cáo ngày/tuần/tháng + Sao chép cho AI (T-025).
            Button { reportKind = model.range == 7 ? .week : (model.range == 30 ? .month : .week) } label: {
                Label("Báo cáo", systemImage: "doc.text.magnifyingglass")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Theme.brand.opacity(0.12), in: Capsule())
                    .foregroundStyle(Theme.brand)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.top, Theme.Space.l)
    }

    private var rangePicker: some View {
        Picker("Khoảng", selection: $model.range) {
            Text("7 ngày").tag(7)
            Text("30 ngày").tag(30)
            Text("90 ngày").tag(90)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Tóm tắt

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = model.sleepSummaryText {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles").foregroundStyle(Theme.brand).padding(.top, 2)
                    Text(text).font(.callout.weight(.medium)).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Theme.Space.m) {
                statTile("Ngủ đủ 7h", value: "\(model.goodSleepNights)", unit: "/\(model.range) đêm", tint: Theme.sleep)
                if let r = model.rhrAvgDelta {
                    statTile("Nhịp tim TB", value: "\(Int(r.avg.rounded()))", unit: deltaText(r.delta, digits: 0), tint: Theme.heart)
                }
                if let s = model.stepsAvgDelta {
                    statTile("Bước TB", value: TodayViewModel.grouped(Int(s.avg.rounded())), unit: "bước", tint: Theme.steps)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.brand)
    }

    private func statTile(_ title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            Text(value).font(.number(24)).foregroundStyle(Theme.textPrimary)
            Text(unit).font(.caption2).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }

    private func deltaText(_ d: Double, digits: Int) -> String {
        if abs(d) < (digits == 0 ? 0.5 : 0.05) { return "ngang kỳ trước" }
        let arrow = d > 0 ? "▲" : "▼"
        return "\(arrow) \(TodayViewModel.decimal(abs(d), digits: digits)) so kỳ trước"
    }

    // MARK: - Biểu đồ giấc ngủ

    private var sleepChartCard: some View {
        chartCard(title: "Giấc ngủ", symbol: "bed.double.fill", tint: Theme.sleep,
                  trailing: selectedSleepDetail) {
            Chart {
                RuleMark(y: .value("Mục tiêu", Thresholds.sleepGoalHours))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.good.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("7 giờ").font(.caption2).foregroundStyle(Theme.good)
                    }
                ForEach(model.sleep) { day in
                    BarMark(x: .value("Ngày", day.date, unit: .day),
                            y: .value("Giờ", day.hours))
                        .foregroundStyle(day.level.color.gradient)
                        .cornerRadius(4)
                }
                ForEach(Array(alcoholDays), id: \.self) { d in
                    if d >= model.sleep.first?.date ?? .distantFuture {
                        RuleMark(x: .value("Ngày", d, unit: .day))
                            .foregroundStyle(Theme.improve.opacity(0.18))
                            .annotation(position: .bottom) {
                                Image(systemName: "wineglass.fill")
                                    .font(.system(size: 9)).foregroundStyle(Theme.improve)
                            }
                    }
                }
            }
            .chartYScale(domain: 0...9)
            .chartXSelection(value: $selectedSleepDate)
            .frame(height: 170)
            .modifier(DayAxis(range: model.range))

            if let sel = selectedSleepDate,
               let day = model.sleep.min(by: {
                   abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel))
               }) {
                Button { night = NightRef(date: day.date) } label: {
                    HStack {
                        Text("Xem chi tiết đêm \(dayMonth(day.date))")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        Image(systemName: "chevron.right").font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.sleep)
            }
        }
    }

    private func dayMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
        return f.string(from: d)
    }

    private var selectedSleepDetail: String? {
        guard let sel = selectedSleepDate,
              let day = model.sleep.min(by: {
                  abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel))
              }) else { return nil }
        var parts = ["\(TodayViewModel.decimal(day.hours, digits: 1)) giờ"]
        if let b = day.summary.bedTime, let w = day.summary.wakeTime {
            parts.append("\(TodayViewModel.time(b))→\(TodayViewModel.time(w))")
        }
        parts.append(day.summary.awakeCount == 0 ? "không thức" : "thức \(day.summary.awakeCount) lần")
        return parts.joined(separator: " · ")
    }

    // MARK: - Nhịp tim nghỉ

    private var rhrChartCard: some View {
        chartCard(title: "Nhịp tim nghỉ", symbol: "heart.fill", tint: Theme.heart, trailing: nil) {
            Chart(model.rhr) { p in
                LineMark(x: .value("Ngày", p.date, unit: .day), y: .value("Nhịp", p.value))
                    .foregroundStyle(Theme.heart)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Ngày", p.date, unit: .day), y: .value("Nhịp", p.value))
                    .foregroundStyle(Thresholds.restingHeartRate(bpm: p.value).color)
                    .symbolSize(60)
            }
            .chartYScale(domain: 50...95)
            .frame(height: 150)
            .modifier(DayAxis(range: model.range))
        }
    }

    // MARK: - Bước

    private var stepsChartCard: some View {
        chartCard(title: "Bước chân", symbol: "figure.walk", tint: Theme.steps, trailing: nil) {
            Chart(model.steps) { p in
                RuleMark(y: .value("Mục tiêu", Double(Thresholds.stepsGoal)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.good.opacity(0.6))
                BarMark(x: .value("Ngày", p.date, unit: .day), y: .value("Bước", p.value))
                    .foregroundStyle(Theme.steps.gradient)
                    .cornerRadius(4)
            }
            .frame(height: 150)
            .modifier(DayAxis(range: model.range))
        }
    }

    // MARK: - Giờ vận động & quãng đường (T-020)

    private var activeHoursChartCard: some View {
        chartCard(title: "Giờ vận động", symbol: "clock.badge.checkmark.fill", tint: Theme.brand,
                  trailing: "Giờ có ≥ 250 bước") {
            Chart(model.activeHours) { p in
                RuleMark(y: .value("Mục tiêu", Double(ActiveHours.goal)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.good.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("9 giờ").font(.caption2).foregroundStyle(Theme.good)
                    }
                BarMark(x: .value("Ngày", p.date, unit: .day), y: .value("Giờ", p.value))
                    .foregroundStyle(Thresholds.activeHours(Int(p.value)).color.gradient)
                    .cornerRadius(4)
            }
            .chartYScale(domain: 0...14)
            .frame(height: 150)
            .modifier(DayAxis(range: model.range))
        }
    }

    private var distanceChartCard: some View {
        chartCard(title: "Quãng đường", symbol: "map.fill", tint: Theme.steps, trailing: "km mỗi ngày") {
            Chart(model.distance) { p in
                RuleMark(y: .value("Mục tiêu", 3.0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.good.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("3 km").font(.caption2).foregroundStyle(Theme.good)
                    }
                BarMark(x: .value("Ngày", p.date, unit: .day), y: .value("km", p.value))
                    .foregroundStyle(Theme.steps.gradient)
                    .cornerRadius(4)
            }
            .frame(height: 150)
            .modifier(DayAxis(range: model.range))
        }
    }

    // MARK: - Cân nặng

    private var weightChartCard: some View {
        chartCard(title: "Cân nặng", symbol: "scalemass.fill", tint: Theme.weight, trailing: nil) {
            Chart(model.weight) { p in
                RuleMark(y: .value("Mục tiêu", Thresholds.weightGoalKg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.good.opacity(0.7))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Mục tiêu " + Thresholds.weightGoalText).font(.caption2).foregroundStyle(Theme.good)
                    }
                LineMark(x: .value("Ngày", p.date, unit: .day), y: .value("kg", p.value))
                    .foregroundStyle(Theme.weight)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Ngày", p.date, unit: .day), y: .value("kg", p.value))
                    .foregroundStyle(Theme.weight)
            }
            .chartYScale(domain: 45...54)
            .frame(height: 150)
            .modifier(DayAxis(range: model.range))
        }
    }

    // MARK: - HRV (biến thiên nhịp tim) — nguồn Google

    private var hrvChartCard: some View {
        chartCard(title: "Biến thiên nhịp tim", symbol: "waveform.path.ecg", tint: Theme.hrv, trailing: nil) {
            Chart(model.hrv) { p in
                LineMark(x: .value("Ngày", p.date, unit: .day), y: .value("HRV", p.value))
                    .foregroundStyle(Theme.hrv)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Ngày", p.date, unit: .day), y: .value("HRV", p.value))
                    .foregroundStyle(Thresholds.heartRateVariability(ms: p.value).color)
                    .symbolSize(50)
            }
            .chartYScale(domain: 10...70)
            .frame(height: 150)
            .modifier(DayAxis(range: model.range))
        }
    }

    // MARK: - Nhiệt độ da — nguồn Google

    private var skinTempChartCard: some View {
        chartCard(title: "Nhiệt độ da", symbol: "thermometer.medium", tint: Theme.temp, trailing: nil) {
            Chart(model.skinTemp) { p in
                RuleMark(y: .value("Nền", 0))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(Theme.good.opacity(0.6))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Nền").font(.caption2).foregroundStyle(Theme.good)
                    }
                LineMark(x: .value("Ngày", p.date, unit: .day), y: .value("Chênh", p.value))
                    .foregroundStyle(Theme.temp)
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Ngày", p.date, unit: .day), y: .value("Chênh", p.value))
                    .foregroundStyle(Thresholds.skinTemperature(delta: p.value).color)
                    .symbolSize(50)
            }
            .chartYScale(domain: -1.4...1.4)
            .frame(height: 150)
            .modifier(DayAxis(range: model.range))
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Image(systemName: "wineglass.fill").font(.caption).foregroundStyle(Theme.improve)
            Text("Ngày có đánh dấu rượu bia (từ Ghi nhanh) để anh thấy tương quan với giấc ngủ.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Khung thẻ biểu đồ

    private func chartCard<Content: View>(title: String, symbol: String, tint: Color,
                                          trailing: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: symbol, tint: tint, size: 32)
                Text(title).font(.cardTitle).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(tint)
                        .multilineTextAlignment(.trailing)
                }
            }
            content()
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint)
    }
}

/// Trục ngày gọn: ít nhãn cho 30 ngày, nhiều hơn cho 7 ngày.
private struct DayAxis: ViewModifier {
    let range: Int
    func body(content: Content) -> some View {
        // Thưa nhãn dần theo khoảng: 7→mỗi ngày, 30→mỗi 6 ngày, 90→mỗi 15 ngày.
        let step = range >= 90 ? 15 : (range >= 30 ? 6 : 1)
        return content.chartXAxis {
            AxisMarks(values: .stride(by: .day, count: step)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(.defaultDigits), centered: false)
            }
        }
    }
}

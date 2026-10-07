import SwiftUI
import SwiftData
import Charts

/// Màn **Giấc ngủ chi tiết**: 1 kết luận lớn → hypnogram → vài số chính → "Tuần này" → đánh giá (gập).
struct SleepDetailView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @State private var model: SleepDetailViewModel
    @State private var showEval = false

    @Query private var alcoholEntries: [LogEntry]

    init(date: Date) {
        self.date = date
        _model = State(initialValue: SleepDetailViewModel(date: date))
    }

    private var hadAlcohol: Bool {
        let day = Calendar.current.startOfDay(for: date)
        return alcoholEntries.contains {
            ($0.amount ?? 0) > 0 && Calendar.current.startOfDay(for: $0.timestamp) == day
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    switch model.state {
                    case .idle, .loading:
                        ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.top, 80)
                    case .empty:
                        emptyView
                    case .failed(let m):
                        Text(m).foregroundStyle(Theme.improve).frame(maxWidth: .infinity).padding(.top, 60)
                    case .loaded:
                        if let d = model.detail { content(d) }
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Giấc ngủ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // T-032: hỏi AI về đêm này (có đủ giai đoạn ngủ + nhật ký ngày).
                    AskAIToolbarButton(date: date, question: "Đêm qua tôi ngủ thế nào? Vì sao thức giấc/dậy sớm, và tối nay nên làm gì khác?")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
            .task { await model.load() }
        }
    }

    @ViewBuilder
    private func content(_ d: SleepDetail) -> some View {
        conclusion(d)
        hypnogramCard(d)
        statsCard(d)
        weekCard
        historyLink
        evalDisclosure(d)
    }

    // MARK: - Lối vào Lịch sử giấc ngủ

    /// Nút mở màn "Lịch sử giấc ngủ" để lật lại nhiều đêm khác.
    private var historyLink: some View {
        NavigationLink {
            SleepHistoryView()
        } label: {
            HStack(spacing: 10) {
                IconBadge(symbol: "calendar.badge.clock", tint: Theme.brand, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Xem các đêm khác")
                        .font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    Text("Lật lại giấc ngủ nhiều đêm gần đây")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold)).foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.brand)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Kết luận lớn

    private func conclusion(_ d: SleepDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(TodayViewModel.decimal(d.asleepHours, digits: 1))
                    .font(.number(46)).foregroundStyle(Theme.textPrimary)
                Text("giờ ngủ").font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                StatusChip(level: Thresholds.sleep(hours: d.asleepHours))
            }
            Text(model.headline)
                .font(.callout).foregroundStyle(Theme.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if let b = d.bedTime, let w = d.wakeTime {
                Label("\(TodayViewModel.time(b)) → \(TodayViewModel.time(w))", systemImage: "moon.stars.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.sleep)
            }
        }
        .padding(Theme.Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.sleep)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - Hypnogram

    private let laneOrder = ["Sâu", "Nông", "REM", "Thức"]

    private func hypnogramCard(_ d: SleepDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Diễn biến đêm", symbol: "waveform.path", tint: Theme.sleep)
            Chart(d.segments) { seg in
                BarMark(
                    xStart: .value("Bắt đầu", seg.start),
                    xEnd: .value("Kết thúc", seg.end),
                    y: .value("Giai đoạn", seg.stage.label),
                    height: 18
                )
                .foregroundStyle(seg.stage.color)
                .cornerRadius(3)
            }
            .chartYScale(domain: laneOrder)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                }
            }
            .frame(height: 180)
            legend(d)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.sleep)
    }

    private func legend(_ d: SleepDetail) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(SleepStage.allCases) { st in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(st.color).frame(width: 12, height: 12)
                    Text(st.label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("\(Int(d.minutes(of: st).rounded())) phút")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Số chính

    private func statsCard(_ d: SleepDetail) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: Theme.Space.m) {
                statTile("Hiệu suất", "\(Int(d.efficiency.rounded()))%",
                         level: d.efficiency >= 85 ? .good : (d.efficiency >= 75 ? .caution : .bad))
                statTile("Vào giấc", "\(Int(d.latencyMinutes.rounded())) phút",
                         level: d.latencyMinutes <= 20 ? .good : (d.latencyMinutes <= 30 ? .caution : .bad))
            }
            HStack(spacing: Theme.Space.m) {
                statTile("Ngủ sâu", "\(Int(d.percent(of: .deep).rounded()))%",
                         level: (13...23).contains(d.percent(of: .deep)) ? .good : .caution)
                statTile("REM", "\(Int(d.percent(of: .rem).rounded()))%",
                         level: d.percent(of: .rem) >= 20 ? .good : .caution)
            }
            if d.awakeCount > 0 {
                let mins = Int(d.awakeMinutes.rounded())
                HStack(spacing: 8) {
                    Image(systemName: "eye.fill").foregroundStyle(Theme.improve)
                    Text("Thức giữa đêm \(d.awakeCount) lần, tổng \(mins) phút")
                        .font(.callout).foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
        }
        .padding(Theme.Space.l)
        .card()
    }

    private func statTile(_ title: String, _ value: String, level: MetricLevel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).font(.number(24)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Circle().fill(level.color).frame(width: 9, height: 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(level.color.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }

    // MARK: - Tuần này

    private var weekCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Tuần này", symbol: "calendar", tint: Theme.brand)
            if let bt = model.avgBedtimeText {
                row("Giờ đi ngủ trung bình", bt + (model.bedtimeStdevMin.map { " (±\(Int($0.rounded())) phút)" } ?? ""))
            }
            if let best = model.bestNight {
                row("Đêm ngon nhất", "\(dm(best.date)) · \(TodayViewModel.decimal(best.hours, digits: 1)) giờ")
            }
            if let worst = model.worstNight {
                row("Đêm kém nhất", "\(dm(worst.date)) · \(TodayViewModel.decimal(worst.hours, digits: 1)) giờ")
            }
            if let dp = model.avgDeepPercent, let rp = model.avgRemPercent {
                row("Sâu / REM trung bình", "\(Int(dp.rounded()))% · \(Int(rp.rounded()))%")
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.brand)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(.callout, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func dm(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
        return f.string(from: d)
    }

    // MARK: - Đánh giá (gập)

    private func evalDisclosure(_ d: SleepDetail) -> some View {
        let evals = Explanations.sleepEvaluations(for: d, bedtimeStdevMin: model.bedtimeStdevMin, hadAlcohol: hadAlcohol)
        return DisclosureGroup(isExpanded: $showEval) {
            VStack(spacing: 10) {
                ForEach(evals) { e in evalRow(e) }
            }
            .padding(.top, 8)
        } label: {
            Label("Đánh giá & lời khuyên", systemImage: "checklist")
                .font(.cardTitle).foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.brand)
        .padding(Theme.Space.l)
        .card()
    }

    private func evalRow(_ e: SleepMetricEval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(e.title).font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(e.value).font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(e.level.color)
            }
            HStack(alignment: .top, spacing: 6) {
                Text(e.isDoctor ? "BS dặn" : "Gợi ý")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(e.isDoctor ? Theme.improve : Theme.caution)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((e.isDoctor ? Theme.improve : Theme.caution).opacity(0.14), in: Capsule())
                Text(e.note).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceMuted.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "bed.double").font(.system(size: 54)).foregroundStyle(Theme.sleep)
            Text("Chưa có dữ liệu giấc ngủ chi tiết cho đêm này.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 70)
    }
}

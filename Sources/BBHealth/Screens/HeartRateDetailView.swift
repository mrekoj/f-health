import SwiftUI
import SwiftData
import Charts

/// Màn **Nhịp tim chi tiết** làm lại theo kiểu Google Health:
/// segmented Ngày / Tuần / Tháng ở đầu màn.
/// - Ngày: nhịp tim theo giờ (trục giờ rõ), đánh dấu cao/thấp nhất, đường nhịp nghỉ,
///   chạm/quét xem giờ+bpm và **ghi chú sự kiện** vào thời điểm đó (lưu SwiftData).
/// - Tuần: 7 ngày, mỗi ngày là dải thấp–cao + chấm nhịp nghỉ; chạm 1 ngày → sang chế độ Ngày.
/// - Tháng: 30 ngày gần nhất, dải thấp–cao + đường nhịp nghỉ (trục ngày thưa).
struct HeartRateDetailView: View {
    let date: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var model: HeartRateDetailViewModel
    @State private var explaining: Metric?
    @State private var showEval = true
    @State private var pickingDate = false        // mở lịch chọn ngày bất kỳ

    // Chọn thời điểm trên biểu đồ.
    @State private var selectedTime: Date?       // điểm đang quét (chỉ có khi đang chạm)
    @State private var pinnedTime: Date?          // điểm đã chọn, GIỮ lại sau khi nhấc tay
    @State private var zoomHours = 24             // mức phóng to biểu đồ Ngày: 24/12/6/3 giờ
    @State private var windowStart: Date?         // mép trái khung đang xem khi zoom (nil = tự canh)
    @State private var selectedWeekDate: Date?   // chế độ Tuần
    @State private var selectedMonthDate: Date?  // chế độ Tháng
    @State private var eventDraft: EventDraft?
    @State private var showingAllEvents = false   // màn "Tất cả ghi chú"
    @State private var showingLive = DebugOptions.showLive   // T-021: màn Nhịp tim trực tiếp

    /// Tất cả ghi chú sự kiện; lọc theo ngày đang xem ở computed `dayEvents`.
    @Query(sort: \HeartEvent.time, order: .forward) private var allEvents: [HeartEvent]

    init(date: Date) {
        self.date = date
        _model = State(initialValue: HeartRateDetailViewModel(date: date))
    }

    private var dayEvents: [HeartEvent] {
        let cal = Calendar.current
        return allEvents.filter { cal.isDate($0.time, inSameDayAs: model.selectedDay) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    modePicker
                    switch model.state {
                    case .idle, .loading:
                        ProgressView().controlSize(.large).frame(maxWidth: .infinity).padding(.top, 60)
                    case .empty:
                        emptyView
                    case .failed(let m):
                        Text(m).foregroundStyle(Theme.improve).frame(maxWidth: .infinity).padding(.top, 60)
                    case .loaded:
                        switch model.mode {
                        case .day:   dayContent
                        case .week:  weekContent
                        case .month: monthContent
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Nhịp tim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAllEvents = true } label: {
                        Label("Ghi chú", systemImage: "note.text")
                    }
                }
                // T-021: đo nhịp tim trực tiếp qua Bluetooth từ vòng.
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingLive = true } label: {
                        Label("Đo trực tiếp", systemImage: "dot.radiowaves.left.and.right")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    // T-032: hỏi AI về nhịp tim ngày đang xem.
                    AskAIToolbarButton(date: model.selectedDay, question: "Nhịp tim hôm nay có gì bất thường không? Lúc nào cao nhất/thấp nhất và vì sao?")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingLive) { LiveHeartRateView() }
            .task { await model.load() }
            .onChange(of: model.mode) { selectedTime = nil; pinnedTime = nil; windowStart = nil; selectedWeekDate = nil; selectedMonthDate = nil; Task { await model.load() } }
            .onChange(of: model.selectedDay) { selectedTime = nil; pinnedTime = nil; windowStart = nil; Task { await model.load() } }
            .onChange(of: zoomHours) { windowStart = nil }
            // Giữ điểm đã chọn sau khi nhấc tay: chỉ cập nhật khi đang quét (non-nil).
            .onChange(of: selectedTime) { if let t = selectedTime { pinnedTime = t } }
            .onChange(of: model.weekAnchor) { selectedWeekDate = nil; Task { await model.load() } }
            .sheet(item: $explaining) { metric in
                ExplanationSheet(metric: metric, value: value(for: metric),
                                 level: level(for: metric), todayNote: todayNote(for: metric))
            }
            .sheet(item: $eventDraft) { draft in
                HeartEventEditor(draft: draft, onSave: saveEvent, onDelete: deleteEvent)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $pickingDate) {
                NavigationStack {
                    DatePicker("Chọn ngày",
                               selection: Binding(get: { model.selectedDay },
                                                  set: { model.showDay($0); pickingDate = false }),
                               in: ...Date(),
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .environment(\.locale, Locale(identifier: "vi_VN"))
                        .padding()
                        .navigationTitle("Chọn ngày xem")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Xong") { pickingDate = false }.fontWeight(.semibold)
                            }
                        }
                    Spacer()
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingAllEvents) {
                HeartAllEventsView(
                    events: allEvents,
                    onOpen: { date in model.showDay(date); showingAllEvents = false },
                    onDelete: deleteEvent)
            }
        }
    }

    // MARK: - Segmented Ngày / Tuần / Tháng

    private var modePicker: some View {
        Picker("Chế độ xem", selection: $model.mode) {
            ForEach(HeartMode.allCases) { m in Text(m.label).tag(m) }
        }
        .pickerStyle(.segmented)
        .padding(.top, Theme.Space.s)
    }

    // MARK: - CHẾ ĐỘ NGÀY

    @ViewBuilder
    private var dayContent: some View {
        dayNavRow
        if let d = model.dayDetail {
            conclusion(d)
            if d.hasIntraday {
                intradayCard(d)
                eventsCard
            } else {
                noIntradayNote
            }
            if model.usesGoogle, d.hrv != nil { hrvCard(d) }
            evalDisclosure(d)
        }
    }

    /// Bộ chọn ngày: lùi/tiến, không cho sang tương lai.
    private var dayNavRow: some View {
        HStack {
            Button { model.goPrevDay() } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold))
                    .frame(width: 40, height: 40).background(Theme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Button { pickingDate = true } label: {
                VStack(spacing: 2) {
                    HStack(spacing: 5) {
                        Text(dayTitle(model.selectedDay)).font(.cardTitle).foregroundStyle(Theme.textPrimary)
                        Image(systemName: "calendar").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.heart)
                    }
                    Text(Calendar.current.isDateInToday(model.selectedDay) ? "Hôm nay" : "Chạm để chọn ngày")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button { model.goNextDay() } label: {
                Image(systemName: "chevron.right").font(.headline.weight(.bold))
                    .frame(width: 40, height: 40).background(Theme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoNextDay)
            .opacity(model.canGoNextDay ? 1 : 0.35)
        }
    }

    // MARK: - Kết luận lớn (Ngày)

    private func conclusion(_ d: HeartRateDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: Metric.restingHeartRate.symbol, tint: Theme.heart)
                Text("Nhịp tim nghỉ").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                Spacer()
                HelpButton(title: "Nhịp tim nghỉ") { explaining = .restingHeartRate }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(d.restingBpm.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.number(46)).foregroundStyle(Theme.textPrimary)
                Text("lần/phút").font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                StatusChip(level: Thresholds.restingHeartRate(bpm: d.restingBpm))
            }
            Text(model.headline)
                .font(.callout).foregroundStyle(Theme.textPrimary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            if let r = model.rangeText {
                Label(r, systemImage: "arrow.up.and.down")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.heart)
            }
        }
        .padding(Theme.Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart)
    }

    // MARK: - Nhịp tim theo giờ (intraday) — chế độ Ngày

    private func intradayCard(_ d: HeartRateDetail) -> some View {
        let lo = ((d.minBpm ?? d.restingBpm ?? 50) - 8)
        let hi = ((d.maxBpm ?? d.restingBpm ?? 100) + 10)
        let selBpm = pinnedTime.flatMap { model.bpm(at: $0) }
        let strideH = zoomHours >= 24 ? 3 : (zoomHours >= 12 ? 2 : 1)
        let windowLen = Double(zoomHours) * 3600
        let fullStart = model.dayStart, fullEnd = model.dayEnd
        let focus = pinnedTime ?? d.maxPoint?.time ?? d.intraday.last?.time ?? fullStart
        let maxStart = max(fullStart, fullEnd.addingTimeInterval(-windowLen))
        let autoStart = min(max(focus.addingTimeInterval(-windowLen / 2), fullStart), maxStart)
        let winStart = zoomHours >= 24 ? fullStart : min(max(windowStart ?? autoStart, fullStart), maxStart)
        let winEnd = zoomHours >= 24 ? fullEnd : winStart.addingTimeInterval(windowLen)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SectionHeader(title: "Nhịp tim theo giờ", symbol: "waveform.path.ecg", tint: Theme.heart)
                Spacer()
                if zoomHours < 24 {
                    panButton(system: "chevron.left", disabled: winStart <= fullStart) {
                        windowStart = max(fullStart, winStart.addingTimeInterval(-windowLen / 2))
                    }
                    panButton(system: "chevron.right", disabled: winStart >= maxStart) {
                        windowStart = min(maxStart, winStart.addingTimeInterval(windowLen / 2))
                    }
                }
                zoomPicker
            }

            Chart {
                // Đường nhịp tim nghỉ tham chiếu.
                if let resting = d.restingBpm {
                    RuleMark(y: .value("Nghỉ", resting))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.good.opacity(0.7))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("nghỉ \(Int(resting.rounded()))").font(.caption2).foregroundStyle(Theme.good)
                        }
                }
                // Đường + vùng nhịp tim trong ngày.
                ForEach(d.intraday) { p in
                    LineMark(x: .value("Giờ", p.time), y: .value("Nhịp", p.bpm))
                        .foregroundStyle(Theme.heart.gradient)
                        .interpolationMethod(.catmullRom)
                    AreaMark(x: .value("Giờ", p.time),
                             yStart: .value("Đáy", lo), yEnd: .value("Nhịp", p.bpm))
                        .foregroundStyle(LinearGradient(colors: [Theme.heart.opacity(0.20), Theme.heart.opacity(0.02)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.catmullRom)
                }
                // Đánh dấu điểm cao nhất & thấp nhất.
                if let mn = d.minPoint { extremeMark(mn, label: "thấp", color: Theme.good, position: .bottom) }
                if let mx = d.maxPoint { extremeMark(mx, label: "cao", color: Theme.improve, position: .top) }
                // Marker ghi chú sự kiện.
                ForEach(dayEvents) { ev in
                    let y = ev.bpm ?? d.restingBpm ?? ((lo + hi) / 2)
                    RuleMark(x: .value("Giờ", ev.time))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Theme.brand.opacity(0.35))
                    PointMark(x: .value("Giờ", ev.time), y: .value("Nhịp", y))
                        .symbolSize(90)
                        .foregroundStyle(Theme.brand)
                        .annotation(position: .top) {
                            Image(systemName: "note.text").font(.caption2.weight(.bold))
                                .foregroundStyle(Theme.brand)
                        }
                }
                // Vạch chọn (giữ lại cả sau khi nhấc tay).
                if let sel = pinnedTime {
                    RuleMark(x: .value("Giờ", sel))
                        .foregroundStyle(Theme.textSecondary.opacity(0.5))
                }
            }
            .chartXScale(domain: winStart...winEnd)
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: strideH)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour(.twoDigits(amPM: .omitted)))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        // Chạm = chọn điểm; giữ & kéo = rê con trỏ qua từng điểm.
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let frame = proxy.plotFrame else { return }
                                    let x = value.location.x - geo[frame].origin.x
                                    if let t: Date = proxy.value(atX: x) {
                                        selectedTime = t; pinnedTime = t
                                    }
                                }
                        )
                        // Chụm 2 ngón = phóng to / thu nhỏ.
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onEnded { scale in
                                    let order = [24, 12, 6, 3]
                                    guard let i = order.firstIndex(of: zoomHours) else { return }
                                    if scale > 1.25, i < order.count - 1 { zoomHours = order[i + 1]; windowStart = nil }
                                    else if scale < 0.8, i > 0 { zoomHours = order[i - 1]; windowStart = nil }
                                }
                        )
                }
            }
            .frame(height: 220)

            calloutRow(selBpm: selBpm)

            Text("**Chạm** để chọn điểm, **giữ & kéo** để rê con trỏ qua từng điểm, rồi bấm \u{201C}Ghi chú sự kiện\u{201D}. **Chụm 2 ngón** (hoặc nút kính lúp) để phóng to; khi đã phóng to, dùng **‹ ›** để trượt khung giờ.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart)
    }

    /// Nút trượt khung giờ khi đã phóng to.
    private func panButton(system: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.subheadline.weight(.bold)).foregroundStyle(Theme.brand)
                .frame(width: 32, height: 32).background(Theme.surfaceMuted, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
    }

    /// Chọn mức phóng to biểu đồ Ngày.
    private var zoomPicker: some View {
        Menu {
            Picker("Phóng to", selection: $zoomHours) {
                Text("Cả ngày").tag(24)
                Text("12 giờ").tag(12)
                Text("6 giờ").tag(6)
                Text("3 giờ").tag(3)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus.magnifyingglass")
                Text(zoomHours >= 24 ? "Cả ngày" : "\(zoomHours) giờ")
            }
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.brand)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.brand.opacity(0.12), in: Capsule())
        }
    }

    private func extremeMark(_ p: HeartRatePoint, label: String, color: Color,
                             position: AnnotationPosition) -> some ChartContent {
        PointMark(x: .value("Giờ", p.time), y: .value("Nhịp", p.bpm))
            .symbolSize(70)
            .foregroundStyle(color)
            .annotation(position: position, spacing: 2) {
                VStack(spacing: 0) {
                    Text("\(Int(p.bpm.rounded()))").font(.caption2.weight(.bold)).foregroundStyle(color)
                    Text("\(label) · \(TodayViewModel.time(p.time))").font(.system(size: 9)).foregroundStyle(Theme.textSecondary)
                }
            }
    }

    /// Dòng callout + nút ghi chú khi đã chọn 1 thời điểm.
    @ViewBuilder
    private func calloutRow(selBpm: Double?) -> some View {
        if let sel = pinnedTime {
            let nearby = nearbyEvent(to: sel)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(TodayViewModel.time(sel)).font(.system(.callout, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let b = selBpm {
                        Text("\(Int(b.rounded())) lần/phút").font(.caption).foregroundStyle(Theme.heart)
                    }
                    if let ev = nearby {
                        Text("Ghi chú: \(ev.note)").font(.caption).foregroundStyle(Theme.brand)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Button {
                    if let ev = nearby {
                        eventDraft = EventDraft(time: ev.time, bpm: ev.bpm, existing: ev)
                    } else {
                        eventDraft = EventDraft(time: sel, bpm: selBpm, existing: nil)
                    }
                } label: {
                    Label(nearby == nil ? "Ghi chú sự kiện" : "Sửa ghi chú",
                          systemImage: nearby == nil ? "plus.circle.fill" : "pencil.circle.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.brand)
                .controlSize(.small)
                Button { pinnedTime = nil; selectedTime = nil } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                        .foregroundStyle(Theme.textSecondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Theme.surfaceMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
        }
    }

    private func nearbyEvent(to time: Date) -> HeartEvent? {
        dayEvents.min(by: { abs($0.time.timeIntervalSince(time)) < abs($1.time.timeIntervalSince(time)) })
            .flatMap { abs($0.time.timeIntervalSince(time)) <= 15 * 60 ? $0 : nil }
    }

    /// Danh sách ghi chú trong ngày (giờ · bpm · nội dung); chạm để sửa, nút xoá.
    @ViewBuilder
    private var eventsCard: some View {
        if !dayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "Ghi chú trong ngày", symbol: "note.text", tint: Theme.brand)
                ForEach(dayEvents) { ev in
                    HStack(spacing: 10) {
                        Button {
                            eventDraft = EventDraft(time: ev.time, bpm: ev.bpm, existing: ev)
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(TodayViewModel.time(ev.time))
                                        .font(.number(16, weight: .semibold)).foregroundStyle(Theme.brand)
                                    if let b = ev.bpm {
                                        Text("\(Int(b.rounded())) bpm").font(.caption2).foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .frame(width: 58, alignment: .leading)
                                Text(ev.note).font(.callout).foregroundStyle(Theme.textPrimary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) { deleteEvent(ev) } label: {
                            Image(systemName: "trash").font(.subheadline).foregroundStyle(Theme.improve)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 6)
                    if ev.id != dayEvents.last?.id { Divider() }
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.brand)
        }
    }

    private var noIntradayNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Chưa có nhịp tim theo giờ cho ngày này", systemImage: "waveform.path.ecg")
                .font(.cardTitle).foregroundStyle(Theme.textPrimary)
            Text("Nguồn dữ liệu hiện chưa có nhịp tim chi tiết trong ngày. Anh vẫn xem được nhịp tim nghỉ ở trên, và dải thấp–cao mỗi ngày ở chế độ Tuần/Tháng.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - CHẾ ĐỘ TUẦN

    @ViewBuilder
    private var weekContent: some View {
        weekNavRow
        rangeChartCard(
            ranges: model.weekRanges,
            title: "Dải nhịp tim theo ngày",
            caption: "Mỗi thanh là khoảng thấp–cao trong ngày; chấm là nhịp tim nghỉ. Chạm 1 ngày để xem chi tiết.",
            restingAsLine: false,
            axisWeekday: true,
            selection: $selectedWeekDate)
    }

    private var weekNavRow: some View {
        HStack {
            Button { model.goPrevWeek() } label: {
                Image(systemName: "chevron.left").font(.headline.weight(.bold))
                    .frame(width: 40, height: 40).background(Theme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text(weekTitle).font(.cardTitle).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { model.goNextWeek() } label: {
                Image(systemName: "chevron.right").font(.headline.weight(.bold))
                    .frame(width: 40, height: 40).background(Theme.surfaceMuted, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canGoNextWeek)
            .opacity(model.canGoNextWeek ? 1 : 0.35)
        }
    }

    // MARK: - CHẾ ĐỘ THÁNG

    @ViewBuilder
    private var monthContent: some View {
        Text("30 ngày gần nhất")
            .font(.cardTitle).foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
        rangeChartCard(
            ranges: model.monthRanges,
            title: "Dải nhịp tim theo ngày",
            caption: "Mỗi thanh là khoảng thấp–cao trong ngày; đường liền là nhịp tim nghỉ. Chạm 1 cột để xem số.",
            restingAsLine: true,
            axisWeekday: false,
            selection: $selectedMonthDate)
    }

    /// Một ô số nhỏ trong callout cột Tuần/Tháng (nhãn + giá trị bpm).
    private func rangeStat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(color)
                Text("bpm").font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Thẻ biểu đồ dải (dùng chung Tuần/Tháng)

    @ViewBuilder
    private func rangeChartCard(ranges: [HeartDayRange], title: String, caption: String,
                                restingAsLine: Bool, axisWeekday: Bool,
                                selection: Binding<Date?>) -> some View {
        let (lo, hi) = rangeDomain(ranges)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeader(title: title, symbol: "waveform.path.ecg", tint: Theme.heart)
                HelpButton(title: "Nhịp tim nghỉ") { explaining = .restingHeartRate }
            }
            if let avg = model.averageResting(ranges) {
                Label("Nhịp tim nghỉ trung bình \(Int(avg.rounded())) lần/phút",
                      systemImage: "heart.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.heart)
            }
            let cal = Calendar.current
            let selDay = selection.wrappedValue
            Chart {
                ForEach(ranges) { r in
                    // Cột đang chọn tô đậm hơn để thấy rõ "focus".
                    let isSel = selDay.map { cal.isDate($0, inSameDayAs: r.date) } ?? false
                    BarMark(x: .value("Ngày", r.date, unit: .day),
                            yStart: .value("Thấp", r.min),
                            yEnd: .value("Cao", r.max),
                            width: .fixed(axisWeekday ? 16 : 6))
                        .foregroundStyle(Theme.heart.opacity(isSel ? 0.95 : 0.45))
                        .cornerRadius(4)
                    if let resting = r.resting, !restingAsLine {
                        PointMark(x: .value("Ngày", r.date, unit: .day), y: .value("Nghỉ", resting))
                            .symbolSize(50)
                            .foregroundStyle(Thresholds.restingHeartRate(bpm: resting).color)
                    }
                }
                if restingAsLine {
                    ForEach(ranges) { r in
                        if let resting = r.resting {
                            LineMark(x: .value("Ngày", r.date, unit: .day), y: .value("Nghỉ", resting))
                                .foregroundStyle(Theme.heart)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                }
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                if axisWeekday {
                    AxisMarks(values: .stride(by: .day, count: 1)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                    }
                } else {
                    AxisMarks(values: .stride(by: .day, count: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.day().month(.defaultDigits))
                    }
                }
            }
            // Chạm (hoặc kéo) vào cột = chọn ngày đó — không cần giữ lâu. (Bỏ chartXSelection vì
            // nó chỉ nhận giữ-kéo, PO bấm thường không chọn được.)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    guard let frame = proxy.plotFrame else { return }
                                    let x = value.location.x - geo[frame].origin.x
                                    guard let t: Date = proxy.value(atX: x),
                                          let r = ranges.min(by: { abs($0.date.timeIntervalSince(t)) < abs($1.date.timeIntervalSince(t)) })
                                    else { return }
                                    if selection.wrappedValue.map({ cal.isDate($0, inSameDayAs: r.date) }) != true {
                                        selection.wrappedValue = r.date
                                    }
                                }
                        )
                }
            }
            .frame(height: 200)

            if let sel = selDay,
               let r = ranges.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) }) {
                // Số của cột đang chọn + nút mở chi tiết ngày đó.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 14) {
                        rangeStat("Thấp nhất", "\(Int(r.min.rounded()))", Theme.good)
                        rangeStat("Cao nhất", "\(Int(r.max.rounded()))", Theme.improve)
                        if let resting = r.resting {
                            rangeStat("Nghỉ", "\(Int(resting.rounded()))", Thresholds.restingHeartRate(bpm: resting).color)
                        }
                        Spacer()
                    }
                    Button { model.showDay(r.date) } label: {
                        HStack {
                            Text("Xem chi tiết ngày \(dayMonth(r.date))")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.heart)
                }
                .padding(10)
                .background(Theme.surfaceMuted.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
            }

            Text(caption)
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart)
    }

    private func rangeDomain(_ ranges: [HeartDayRange]) -> (Double, Double) {
        let mins = ranges.map(\.min)
        let maxs = ranges.map(\.max)
        guard let lo = mins.min(), let hi = maxs.max() else { return (40, 140) }
        return (max(35, lo - 6), hi + 8)
    }

    // MARK: - HRV (giữ như cũ, chỉ hiện ở chế độ Ngày)

    private func hrvCard(_ d: HeartRateDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconBadge(symbol: Metric.heartRateVariability.symbol, tint: Theme.hrv)
                Text("Biến thiên nhịp tim").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                Spacer()
                HelpButton(title: "Biến thiên nhịp tim") { explaining = .heartRateVariability }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(model.hrvValueText).font(.number(34)).foregroundStyle(Theme.textPrimary)
                Text("ms").font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                StatusChip(level: Thresholds.heartRateVariability(ms: d.hrv))
            }
            Text("Số cao và ổn định là cơ thể hồi phục tốt. Chỉ nguồn Google Health mới có số này.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.hrv)
    }

    // MARK: - Đánh giá (gập)

    private func evalDisclosure(_ d: HeartRateDetail) -> some View {
        let evals = Explanations.heartEvaluations(for: d)
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

    private func evalRow(_ e: HeartMetricEval) -> some View {
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
                Text(.init(e.note)).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surfaceMuted.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart").font(.system(size: 54)).foregroundStyle(Theme.heart)
            Text("Chưa có dữ liệu nhịp tim cho khoảng này.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }

    // MARK: - Ghi chú sự kiện (SwiftData)

    private func saveEvent(_ draft: EventDraft, note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let ev = draft.existing {
            ev.note = trimmed
        } else {
            context.insert(HeartEvent(time: draft.time, note: trimmed, bpm: draft.bpm))
        }
    }

    private func deleteEvent(_ event: HeartEvent) {
        context.delete(event)
    }

    // MARK: - Định dạng ngày

    private func dayTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EEEE, d/M"
        return f.string(from: d).capitalized
    }
    private func dayMonth(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "d/M"
        return f.string(from: d)
    }
    private var weekTitle: String {
        let start = model.weekStart
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        if Calendar.current.isDate(start, equalTo: Calendar.current.dateInterval(of: .weekOfYear, for: model.today)?.start ?? start, toGranularity: .day) {
            return "Tuần này"
        }
        return "\(dayMonth(start)) – \(dayMonth(end))"
    }

    // MARK: - Dữ liệu cho sheet giải thích

    private func value(for metric: Metric) -> String {
        switch metric {
        case .restingHeartRate: return model.dayDetail?.restingBpm.map { "\(Int($0.rounded()))" } ?? "—"
        case .heartRateVariability: return model.hrvValueText
        default: return "—"
        }
    }

    private func level(for metric: Metric) -> MetricLevel {
        switch metric {
        case .restingHeartRate: return Thresholds.restingHeartRate(bpm: model.dayDetail?.restingBpm)
        case .heartRateVariability: return Thresholds.heartRateVariability(ms: model.dayDetail?.hrv)
        default: return .unknown
        }
    }

    private func todayNote(for metric: Metric) -> String {
        switch metric {
        case .restingHeartRate: return model.headline
        case .heartRateVariability:
            guard model.dayDetail?.hrv != nil else { return "Chưa có số HRV (cần nguồn Google Health)." }
            switch level(for: .heartRateVariability) {
            case .good: return "HRV \(model.hrvValueText) ms — cơ thể hồi phục tốt. Giữ nếp ngủ và tránh rượu bia buổi tối."
            case .caution: return "HRV \(model.hrvValueText) ms — ở mức vừa. Nhìn xu hướng vài ngày; nếu tụt dần thì để ý ngủ và rượu bia."
            default: return "HRV \(model.hrvValueText) ms — thấp so với thường ngày. Hôm nay nên nghỉ ngơi, uống đủ nước, tránh rượu bia."
            }
        default: return ""
        }
    }
}

// MARK: - Màn "Tất cả ghi chú" (gộp mọi ngày)

/// Danh sách mọi ghi chú sự kiện, nhóm theo ngày (mới nhất trên đầu); chạm 1 ghi chú để mở ngày đó.
private struct HeartAllEventsView: View {
    @Environment(\.dismiss) private var dismiss
    let events: [HeartEvent]
    let onOpen: (Date) -> Void
    let onDelete: (HeartEvent) -> Void

    private var grouped: [(day: Date, items: [HeartEvent])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: events) { cal.startOfDay(for: $0.time) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0]!.sorted { $0.time > $1.time }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if events.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "note.text").font(.system(size: 50)).foregroundStyle(Theme.brand)
                        Text("Chưa có ghi chú sự kiện nào.")
                            .font(.title3).foregroundStyle(Theme.textSecondary)
                        Text("Ở tab Ngày, chạm vào biểu đồ nhịp tim rồi bấm \u{201C}Ghi chú sự kiện\u{201D}.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(grouped, id: \.day) { group in
                            Section(dayHeader(group.day)) {
                                ForEach(group.items) { ev in
                                    Button { onOpen(ev.time) } label: { row(ev) }
                                        .buttonStyle(.plain)
                                        .swipeActions {
                                            Button(role: .destructive) { onDelete(ev) } label: {
                                                Label("Xoá", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tất cả ghi chú")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func row(_ ev: HeartEvent) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(TodayViewModel.time(ev.time)).font(.number(16, weight: .semibold)).foregroundStyle(Theme.brand)
                if let b = ev.bpm {
                    Text("\(Int(b.rounded())) bpm").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 60, alignment: .leading)
            Text(ev.note).font(.callout).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func dayHeader(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "vi_VN"); f.dateFormat = "EEEE, d/M/yyyy"
        return f.string(from: d).capitalized
    }
}

// MARK: - Bản nháp ghi chú sự kiện + sheet nhập

/// Dữ liệu tạm cho sheet ghi chú: thời điểm + bpm + (nếu sửa) bản ghi sẵn có.
struct EventDraft: Identifiable {
    let id = UUID()
    var time: Date
    var bpm: Double?
    var existing: HeartEvent?
}

/// Sheet nhập/sửa ghi chú sự kiện tiếng Việt cho một thời điểm nhịp tim.
private struct HeartEventEditor: View {
    let draft: EventDraft
    let onSave: (EventDraft, String) -> Void
    let onDelete: (HeartEvent) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @FocusState private var focused: Bool

    private let suggestions = ["Tập thể dục", "Họp căng thẳng", "Uống cà phê", "Ăn no", "Rượu bia", "Nghỉ ngơi"]

    init(draft: EventDraft, onSave: @escaping (EventDraft, String) -> Void, onDelete: @escaping (HeartEvent) -> Void) {
        self.draft = draft
        self.onSave = onSave
        self.onDelete = onDelete
        _note = State(initialValue: draft.existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "note.text", tint: Theme.brand, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TodayViewModel.time(draft.time))
                                .font(.number(26)).foregroundStyle(Theme.textPrimary)
                            if let b = draft.bpm {
                                Text("\(Int(b.rounded())) lần/phút").font(.callout).foregroundStyle(Theme.heart)
                            }
                        }
                        Spacer()
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(tint: Theme.brand)

                    Text("Lúc đó có chuyện gì?").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    TextField("Vd: họp căng thẳng, tập thể dục…", text: $note, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...4)
                        .focused($focused)
                        .padding(12)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

                    // Gợi ý nhanh.
                    FlowChips(items: suggestions) { note = $0 }

                    if draft.existing != nil {
                        Button(role: .destructive) {
                            if let ev = draft.existing { onDelete(ev) }
                            dismiss()
                        } label: {
                            Label("Xoá ghi chú", systemImage: "trash")
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.improve)
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, Theme.Space.l)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(draft.existing == nil ? "Ghi chú sự kiện" : "Sửa ghi chú")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { onSave(draft, note); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

/// Hàng chip gợi ý tự xuống dòng.
private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button { onTap(item) } label: {
                    Text(item).font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Theme.brand)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.brand.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

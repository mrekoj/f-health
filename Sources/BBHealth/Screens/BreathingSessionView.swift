import SwiftUI
import SwiftData
import Charts
import UIKit

/// **Bài thở** (T-023, T-024): trước khi tập anh chọn 1 trong 7 bài của thư viện (`BreathingPattern.all`
/// — thở chậm 4–6, 5–5, thở bụng, thở dài theo chu kỳ, thở hộp, 4–7–8, thở mũi luân phiên), mỗi bài có
/// sheet Chi tiết (tác dụng, dùng khi nào, cách làm, bằng chứng, lưu ý riêng cho anh). Bài chọn gần nhất được nhớ.
///
/// Khi thở: chạy lần lượt mọi pha của bài — vòng tròn phình khi hít, phình thêm chút khi "hít thêm",
/// đứng yên khi giữ hơi (to sau hít, nhỏ sau thở ra), xẹp khi thở ra; dưới là nhịp tim trực tiếp từ vòng
/// (dùng chung `LiveHeartRateMonitor` của màn Nhịp tim trực tiếp — không mở kết nối mới).
/// Kết thúc / dừng sớm → màn tóm tắt (nhịp tim đầu → cuối, biên độ theo hơi thở, số nhịp thở)
/// và tự lưu `LiveSession` loại "bài thở" (ghi chú = tên bài). Chỉ cần nhịp tim, không cần HRV.
struct BreathingSessionView: View {
    let monitor: LiveHeartRateMonitor
    /// Bắt đầu ngay khi mở (cờ chụp màn hình `-BBHShowBreath`).
    var autoStart = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    private enum Stage { case setup, running, summary }

    /// Kết quả để hiện ở màn tóm tắt.
    private struct Summary {
        let pattern: BreathingPattern
        let minutes: Int
        let startBpm: Int?
        let endBpm: Int?
        let swing: Double?
        let stdev: Double?
        let duration: TimeInterval
        let breaths: Int
        let early: Bool
        let points: [BreathingStats.Point]
        let saved: Bool
    }

    @State private var stage: Stage = .setup
    @State private var pattern: BreathingPattern = .slow46
    @State private var minutes = BreathingPattern.slow46.defaultMinutes
    @State private var loaded = false
    /// Bài chọn gần nhất (T-024).
    @AppStorage("BBHBreathPatternID") private var savedPatternID = BreathingPattern.defaultID
    @AppStorage("BBHBreathHaptics") private var hapticsOn = true

    @State private var startDate: Date?
    @State private var now = Date()
    @State private var points: [BreathingStats.Point] = []
    @State private var startBpm: Int?
    @State private var phaseIndex = -1
    @State private var currentPhase = BreathPhase(.inhale, 4)
    @State private var circleScale: CGFloat = 0.55
    @State private var summary: Summary?
    @State private var showingHelp = false
    @State private var detailPattern: BreathingPattern?
    @State private var noteSaved = false

    private let minScale: CGFloat = 0.55

    private var totalSeconds: TimeInterval { pattern.totalSeconds(minutes: minutes) }
    private var elapsed: TimeInterval {
        guard let startDate else { return 0 }
        return min(max(0, now.timeIntervalSince(startDate)), totalSeconds)
    }

    private var isLive: Bool {
        if case .connected = monitor.state { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            // Thanh Bắt đầu nằm dưới ScrollView (không dùng safeAreaInset: trong sheet nội dung lọt xuống dưới thanh).
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Theme.Space.l) {
                        switch stage {
                        case .setup: setupView
                        case .running: runningView
                        case .summary: if let summary { summaryView(summary) }
                        }
                    }
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.top, Theme.Space.s)
                    .padding(.bottom, Theme.Space.xxl)
                }
                if stage == .setup { startBar }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(stage == .setup ? "Chọn bài thở" : pattern.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(title: "Bài thở") { showingHelp = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if stage == .running {
                        Button("Dừng") { finish(early: true) }.fontWeight(.semibold)
                    } else {
                        Button("Đóng") { dismiss() }.fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $showingHelp) {
                BreathingHelpSheet().presentationDetents([.large])
            }
            .sheet(item: $detailPattern) { p in
                BreathingPatternDetailSheet(pattern: p, selected: p.id == pattern.id,
                                            onChoose: stage == .setup ? { select(p) } : nil)
                    .presentationDetents([.large])
            }
        }
        .interactiveDismissDisabled(stage == .running)
        .onAppear {
            if !loaded {
                loaded = true
                let p = BreathingPattern.find(DebugOptions.breathPattern)
                    ?? BreathingPattern.find(savedPatternID) ?? .slow46
                pattern = p
                minutes = p.defaultMinutes
            }
            if autoStart && !DebugOptions.breathLibrary && stage == .setup { start() }
        }
        .task {
            // Cờ chụp màn hình: mở sẵn Chi tiết của bài đang chọn (sheet lồng sheet cần chờ).
            guard DebugOptions.breathDetail else { return }
            try? await Task.sleep(for: .seconds(1))
            detailPattern = pattern
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            monitor.endSimulatedCalming()
        }
        // Mỗi số mới từ vòng → ghi vào bài.
        .onChange(of: monitor.lastUpdate) { _, t in
            guard stage == .running, isLive, let t, let bpm = monitor.bpm,
                  let startDate, t >= startDate else { return }
            points.append(BreathingStats.Point(time: t, bpm: bpm))
            if startBpm == nil, t.timeIntervalSince(startDate) >= 15 {
                startBpm = BreathingStats.startAverage(points)
            }
        }
        // Nhịp đồng hồ ~5 lần/giây khi đang thở (tự huỷ khi đổi màn).
        .task(id: stage) {
            guard stage == .running else { return }
            while !Task.isCancelled {
                now = Date()
                tick()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
    }

    // MARK: - Điều khiển

    private func select(_ p: BreathingPattern) {
        guard p.id != pattern.id else { return }
        pattern = p
        minutes = p.defaultMinutes
        savedPatternID = p.id
        if hapticsOn { UISelectionFeedbackGenerator().selectionChanged() }
    }

    private func start() {
        points = []
        startBpm = nil
        phaseIndex = -1
        circleScale = minScale
        noteSaved = false
        summary = nil
        savedPatternID = pattern.id
        let begin = Date()
        startDate = begin
        now = begin
        stage = .running
        UIApplication.shared.isIdleTimerDisabled = true   // không tắt màn giữa bài
        let debugEnd = DebugOptions.breathEndAfter
        monitor.beginSimulatedCalming(over: debugEnd > 0 ? TimeInterval(debugEnd) : totalSeconds,
                                      pattern: pattern)
        tick()
    }

    /// Cập nhật pha; đổi pha → chạy animation vòng tròn theo đúng thời gian còn lại của pha + rung nhẹ.
    /// Pha giữ hơi: vòng đứng yên (to sau hít, nhỏ sau thở ra).
    private func tick() {
        guard stage == .running, let startDate else { return }
        let raw = now.timeIntervalSince(startDate)
        let debugEnd = DebugOptions.breathEndAfter
        if raw >= totalSeconds || (debugEnd > 0 && raw >= TimeInterval(debugEnd)) {
            finish(early: raw < totalSeconds)
            return
        }
        let pos = pattern.position(at: raw)
        guard pos.globalIndex != phaseIndex else { return }
        phaseIndex = pos.globalIndex
        currentPhase = pos.phase
        let next = pattern.phases[(pos.index + 1) % pattern.phases.count].kind
        let duration = max(0.3, pos.remaining)
        switch pos.phase.kind {
        case .inhale:
            // Có "hít thêm" phía sau → chừa chỗ cho vòng phình thêm.
            withAnimation(.easeInOut(duration: duration)) { circleScale = next == .inhaleTop ? 0.86 : 1 }
        case .inhaleTop:
            withAnimation(.easeOut(duration: duration)) { circleScale = 1 }
        case .exhale:
            withAnimation(.easeInOut(duration: duration)) { circleScale = minScale }
        case .holdIn, .holdOut:
            break   // đứng yên
        }
        if hapticsOn {
            switch pos.phase.kind {
            case .inhale, .inhaleTop:
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
            case .exhale:
                UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.8)
            case .holdIn, .holdOut:
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.5)
            }
        }
    }

    private func finish(early: Bool) {
        guard stage == .running, let startDate else { return }
        let end = Date()
        let duration = min(end.timeIntervalSince(startDate), totalSeconds)
        let s = BreathingStats.startAverage(points)
        let e = BreathingStats.endAverage(points)
        // Lưu phiên "bài thở" (cần vài mẫu nhịp tim); ghi chú = tên bài.
        var saved = false
        if points.count >= 3,
           let session = LiveSession.make(from: points.map { ($0.time, $0.bpm) },
                                          kind: LiveSession.Kind.breathing, startBpm: s, endBpm: e,
                                          note: "\(pattern.name) · \(minutes) phút") {
            session.start = startDate
            session.end = startDate.addingTimeInterval(duration)
            context.insert(session)
            try? context.save()
            saved = true
        }
        summary = Summary(pattern: pattern, minutes: minutes, startBpm: s, endBpm: e,
                          swing: BreathingStats.breathSwing(points, cycle: pattern.breathPeriod),
                          stdev: BreathingStats.standardDeviation(points),
                          duration: duration, breaths: pattern.breaths(in: duration),
                          early: early, points: points, saved: saved)
        monitor.endSimulatedCalming()
        UIApplication.shared.isIdleTimerDisabled = false
        if hapticsOn { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        withAnimation { circleScale = minScale }
        stage = .summary
    }

    // MARK: - Chọn bài (trước khi bắt đầu)

    private var setupView: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Chạm để chọn một bài, bấm \u{201C}?\u{201D} để xem tác dụng, bằng chứng và lưu ý riêng cho anh.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(BreathingPattern.all) { p in
                patternCard(p)
            }

            Toggle(isOn: $hapticsOn) {
                Text("Rung nhẹ khi đổi pha")
                    .font(.body).foregroundStyle(Theme.textPrimary)
            }
            .tint(Theme.breath)
            .padding(Theme.Space.l)
            .card(radius: 20)
        }
    }

    /// Thẻ một bài: tên · nhịp · 1 câu mục đích · chip bằng chứng (+ "Hợp với anh").
    private func patternCard(_ p: BreathingPattern) -> some View {
        let selected = p.id == pattern.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(selected ? Theme.breath : Theme.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(p.rhythmText)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.breath)
                }
                Spacer(minLength: 0)
                HelpButton(title: p.name) { detailPattern = p }
            }
            Text(p.purpose)
                .font(.body).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                EvidenceChip(evidence: p.evidenceLevel)
                if p.fitsYou {
                    TagChip(text: "Hợp với anh", symbol: "heart.fill", tint: Theme.brand)
                }
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: selected ? Theme.breath : nil, radius: 20)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(selected ? Theme.breath : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { select(p) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Thanh dưới: thời lượng + nút Bắt đầu.
    private var startBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text("Thời lượng").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).fixedSize()
                ForEach(pattern.minuteOptions, id: \.self) { m in
                    optionButton(selected: minutes == m, title: "\(m) phút", subtitle: nil) { minutes = m }
                }
            }
            Button(action: start) {
                Label("Bắt đầu · \(pattern.name)", systemImage: "play.fill")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.breath)
        }
        .padding(.horizontal, Theme.Space.page)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background { Rectangle().fill(.regularMaterial).ignoresSafeArea(edges: .bottom) }
    }

    private func optionButton(selected: Bool, title: String, subtitle: String?,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(2).multilineTextAlignment(.center)
                        .foregroundStyle(selected ? Theme.breath : Theme.textSecondary)
                }
            }
            .foregroundStyle(selected ? Theme.breath : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10).padding(.horizontal, 6)
            .background(selected ? Theme.breath.opacity(0.15) : Theme.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                .stroke(selected ? Theme.breath : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Đang thở

    private var position: BreathingPattern.Position? {
        guard let startDate else { return nil }
        return pattern.position(at: now.timeIntervalSince(startDate))
    }

    /// Số giây còn lại của pha hiện tại.
    private var phaseSecondsLeft: Int {
        guard let position else { return Int(pattern.phases.first?.seconds ?? 4) }
        return max(1, Int(position.remaining.rounded(.up)))
    }

    private var runningView: some View {
        VStack(spacing: Theme.Space.l) {
            breathCircle(title: currentPhase.cue, subtitle: "\(phaseSecondsLeft)", hint: currentPhase.sub)
                .padding(.top, Theme.Space.s)

            // Tiến độ theo phút.
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Phút \(min(minutes, Int(elapsed / 60) + 1))/\(minutes)")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("còn \(LiveSession.durationText(totalSeconds - elapsed))")
                        .font(.system(.headline, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                ProgressBar(progress: elapsed / totalSeconds, tint: Theme.breath, height: 10)
                Text("Nhịp thở thứ \(position?.breathNumber ?? 1) · \(pattern.shortPattern)")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
            .padding(Theme.Space.l)
            .card(radius: 20)

            heartCard
        }
    }

    /// Vòng tròn phình (hít vào) / đứng yên (giữ) / xẹp (thở ra), chữ to ở giữa + gợi ý nhỏ.
    private func breathCircle(title: String, subtitle: String, hint: String? = nil) -> some View {
        ZStack {
            Circle()
                .stroke(Theme.breath.opacity(0.18), style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
            Circle()
                .fill(RadialGradient(colors: [Theme.breath.opacity(0.55), Theme.breath.opacity(0.22)],
                                     center: .center, startRadius: 10, endRadius: 150))
                .overlay(Circle().stroke(Theme.breath.opacity(0.6), lineWidth: 3))
                .scaleEffect(circleScale)
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: title)
                Text(subtitle)
                    .font(.number(30, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText())
                if let hint {
                    Text(hint)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 210)
                        .transition(.opacity)
                        .id(hint)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: hint)
        }
        .frame(width: 280, height: 280)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Nhịp tim trực tiếp + đường cả bài.
    private var heartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "heart.fill").foregroundStyle(Theme.heart)
                    .font(.system(size: 22, weight: .bold))
                if isLive, let bpm = monitor.bpm {
                    Text("\(bpm)")
                        .font(.number(48)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .contentTransition(.numericText(value: Double(bpm)))
                        .animation(.snappy, value: bpm)
                    Text("lần/phút").font(.system(.title3, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text("Mất kết nối với vòng — cứ thở tiếp, bài vẫn chạy")
                        .font(.body).foregroundStyle(Theme.improve)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let startBpm {
                    Text("Lúc đầu \(startBpm)")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.heart)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.heart.opacity(0.15), in: Capsule())
                }
            }
            if points.count >= 2 { sparkline(points, height: 90) }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart, radius: 20)
    }

    private func sparkline(_ pts: [BreathingStats.Point], height: CGFloat) -> some View {
        let lo = (pts.map(\.bpm).min() ?? 60) - 3
        let hi = (pts.map(\.bpm).max() ?? 80) + 3
        return Chart(Array(pts.enumerated()), id: \.offset) { _, p in
            LineMark(x: .value("Giờ", p.time), y: .value("Nhịp", p.bpm))
                .foregroundStyle(Theme.heart)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: lo...hi)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel()
            }
        }
        .frame(height: height)
        .accessibilityLabel("Đường nhịp tim trong bài thở")
    }

    // MARK: - Tóm tắt

    /// Nhịp tim có hạ rõ không (≥ 2 lần/phút).
    private func dropped(_ s: Summary) -> Bool {
        guard let a = s.startBpm, let b = s.endBpm else { return false }
        return b <= a - 2
    }

    private func summaryView(_ s: Summary) -> some View {
        VStack(spacing: Theme.Space.l) {
            // Câu chính: nhịp tim đầu → cuối.
            VStack(spacing: 10) {
                IconBadge(symbol: dropped(s) ? "heart.circle.fill" : "wind",
                          tint: dropped(s) ? Theme.good : Theme.breath, size: 52)
                Text("\(s.early ? "Đã dừng bài thở" : "Xong bài thở") · \(s.pattern.name)")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                headline(s)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if s.points.count >= 2 { sparkline(s.points, height: 80) }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity)
            .card(tint: dropped(s) ? Theme.good : Theme.breath)

            // Ô số liệu.
            HStack(spacing: 8) {
                tile("Thời gian", LiveSession.durationText(s.duration))
                tile("Số nhịp thở", "\(s.breaths)")
                tile("Lên xuống", s.swing.map { "\(Int($0.rounded()))" } ?? "—")
            }

            // Bài có nín thở: con số "lên xuống" ít ý nghĩa (T-024).
            if let m = s.pattern.measureNote {
                Label {
                    Text(m).font(.callout).foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.caution)
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(tint: Theme.caution, radius: 20)
            }

            if let swing = s.swing {
                let n = Explanations.breathSwingNote(swing)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Nhịp tim theo hơi thở").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 0)
                        Text(n.label)
                            .font(.system(.subheadline, design: .rounded).weight(.bold))
                            .foregroundStyle(n.level.color)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(n.level.color.opacity(0.15), in: Capsule())
                    }
                    Text("Mỗi nhịp thở, tim lên xuống khoảng \(Int(swing.rounded())) lần/phút (\(s.duration > 150 ? "2 phút cuối" : "cả bài"))\(s.stdev.map { " · độ lệch " + String(format: "%.1f", $0).replacingOccurrences(of: ".", with: ",") } ?? "").")
                        .font(.callout).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(n.note)
                        .font(.body).foregroundStyle(Theme.textPrimary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(tint: n.level.color, radius: 20)
            }

            if s.saved {
                Label("Đã lưu vào Các phiên đã đo", systemImage: "checkmark.circle.fill")
                    .font(.label).foregroundStyle(Theme.good)
            }

            VStack(spacing: 10) {
                Button { saveNote(s) } label: {
                    Label(noteSaved ? "Đã lưu ghi chú" : "Ghi chú sự kiện",
                          systemImage: noteSaved ? "checkmark" : "note.text.badge.plus")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent).tint(Theme.heart)
                .disabled(noteSaved || s.points.isEmpty)

                Button { start() } label: {
                    Label("Thở thêm một bài", systemImage: "arrow.counterclockwise")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(Theme.breath)

                Button {
                    summary = nil
                    stage = .setup
                } label: {
                    Label("Chọn bài khác", systemImage: "list.bullet")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(Theme.breath)

                Button { dismiss() } label: {
                    Text("Đóng")
                        .font(.system(.headline, design: .rounded))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered).tint(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func headline(_ s: Summary) -> some View {
        if let a = s.startBpm, let b = s.endBpm {
            if dropped(s) {
                VStack(spacing: 4) {
                    (Text("Nhịp tim hạ từ ") + Text("\(a) → \(b)").bold().foregroundColor(Theme.good))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Giảm \(a - b) lần/phút — cơ thể đã dịu lại.")
                        .font(.body).foregroundStyle(Theme.textSecondary)
                }
            } else {
                Text("Nhịp tim giữ ở ~\(b) — bình thường, hãy thử lúc yên tĩnh hơn.")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            }
        } else {
            Text("Chưa nhận được nhịp tim trong bài này. Bài thở vẫn có ích — lần sau để vòng gần điện thoại.")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.number(26)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Theme.textPrimary)
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    private func saveNote(_ s: Summary) {
        var note = "Bài thở \u{201C}\(s.pattern.name)\u{201D} · \(s.minutes) phút"
        if let a = s.startBpm, let b = s.endBpm { note += " — nhịp tim \(a)→\(b)" }
        let time = s.points.last?.time ?? Date()
        let bpm = s.endBpm ?? s.points.last?.bpm
        context.insert(HeartEvent(time: time, note: note, bpm: bpm.map(Double.init)))
        try? context.save()
        noteSaved = true
    }
}

// MARK: - Chip mức bằng chứng

/// "Bằng chứng: Mạnh" (xanh) · "Vừa" (vàng) · "Còn ít" (xám).
private struct EvidenceChip: View {
    let evidence: BreathEvidence

    var body: some View {
        let c = evidence.level.color
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text("Bằng chứng: \(evidence.label)").lineLimit(1).fixedSize()
        }
        .font(.system(.footnote, design: .rounded).weight(.semibold))
        .foregroundStyle(c)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(c.opacity(0.14), in: Capsule())
    }
}

// MARK: - Chi tiết một bài

/// Sheet đầy đủ của một bài: tác dụng, dùng khi nào, cách làm, bằng chứng, lưu ý, riêng cho anh.
private struct BreathingPatternDetailSheet: View {
    let pattern: BreathingPattern
    var selected = false
    /// Có → hiện nút "Chọn bài này" (chỉ ở màn chọn bài).
    var onChoose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        header
                        BreathSection(title: "Tác dụng", symbol: "sparkles", tint: Theme.breath) {
                            Text(pattern.purpose).bodyText()
                        }
                        BreathSection(title: "Dùng khi nào", symbol: "clock.fill", tint: Theme.brand) {
                            BulletList(items: pattern.bestFor)
                        }
                        BreathSection(title: "Cách làm", symbol: "figure.mind.and.body", tint: Theme.breath) {
                            Text(pattern.howTo).bodyText()
                        }
                        BreathSection(title: "Bằng chứng khoa học", symbol: "books.vertical.fill",
                                      tint: pattern.evidenceLevel.level.color) {
                            EvidenceChip(evidence: pattern.evidenceLevel)
                            Text(pattern.evidenceNote).bodyText()
                        }
                        if !pattern.cautions.isEmpty {
                            BreathSection(title: "Lưu ý", symbol: "exclamationmark.triangle.fill", tint: Theme.caution) {
                                BulletList(items: pattern.cautions)
                            }
                        }
                        BreathSection(title: "Riêng cho anh", symbol: "person.fill.checkmark", tint: Theme.improve) {
                            Text(pattern.forYou).bodyText()
                        }
                        if let m = pattern.measureNote {
                            BreathSection(title: "Con số sau bài", symbol: "heart.text.square.fill", tint: Theme.heart) {
                                Text(m).bodyText()
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.vertical, Theme.Space.l)
                }
                if let onChoose {
                    Button {
                        onChoose()
                        dismiss()
                    } label: {
                        Label(selected ? "Đang chọn bài này" : "Chọn bài này",
                              systemImage: selected ? "checkmark" : "hand.tap.fill")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.breath)
                    .disabled(selected)
                    .padding(.horizontal, Theme.Space.page)
                    .padding(.vertical, 10)
                    .background { Rectangle().fill(.regularMaterial).ignoresSafeArea(edges: .bottom) }
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Chi tiết bài thở")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pattern.name)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(pattern.rhythmText)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.breath)
            if pattern.fitsYou {
                TagChip(text: "Hợp với anh", symbol: "heart.fill", tint: Theme.brand)
            }
        }
    }
}

/// Một khối có tiêu đề + icon trong sheet bài thở.
private struct BreathSection<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).font(.cardTitle)
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(tint)
            content
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint, radius: 20)
    }
}

/// Danh sách gạch đầu dòng chữ to.
private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").font(.body.weight(.bold)).foregroundStyle(Theme.textSecondary)
                    Text(item).bodyText()
                }
            }
        }
    }
}

private extension Text {
    func bodyText() -> some View {
        self.font(.body).foregroundStyle(Theme.textPrimary).lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Giải thích "?" của cả thư viện

/// Vì sao thở chậm giúp dịu, chọn bài theo lúc, vì sao không có bài thở nhanh, không thay thuốc/BS.
private struct BreathingHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let e = Explanations.breathing

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    BreathSection(title: "Vì sao thở chậm giúp dịu", symbol: "wind", tint: Theme.breath) {
                        Text(e.plain).bodyText()
                    }
                    if let d = e.doctorNote {
                        BreathSection(title: "BS dặn", symbol: "stethoscope", tint: Theme.improve) {
                            Text(d).bodyText()
                        }
                    }
                    BreathSection(title: "Chọn bài theo lúc", symbol: "list.bullet.rectangle.fill", tint: Theme.brand) {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(BreathingPattern.chooser, id: \.situation) { row in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.situation)
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(row.ids.compactMap { BreathingPattern.find($0)?.name }.joined(separator: " · "))
                                        .font(.body).foregroundStyle(Theme.breath)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    BreathSection(title: "Vì sao không có bài thở nhanh", symbol: "hand.raised.fill", tint: Theme.caution) {
                        Text(Explanations.breathingExcluded).bodyText()
                    }
                    BreathSection(title: "Con số sau bài thở", symbol: "heart.text.square.fill", tint: Theme.heart) {
                        Text("App so nhịp tim trung bình 15 giây đầu với 30 giây cuối. Mục \u{201C}Lên xuống\u{201D} là tim nhanh lên khi hít vào, chậm lại khi thở ra — lên xuống càng rõ thì cơ thể càng đang thư giãn tốt. Bài có nín thở (thở hộp, 4–7–8) thì xem nhịp tim hạ là chính. Số đo từ vòng đeo tay, chỉ để tham khảo.").bodyText()
                    }
                    BreathSection(title: "Gợi ý", symbol: "lightbulb.fill", tint: Theme.caution) {
                        Text(e.tip).bodyText()
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, Theme.Space.l)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Thư viện bài thở")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

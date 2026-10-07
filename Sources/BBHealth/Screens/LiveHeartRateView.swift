import SwiftUI
import SwiftData
import Charts
import UIKit

/// Màn **Nhịp tim trực tiếp** (T-021): nhận bpm qua Bluetooth từ vòng Fitbit Air khi anh bật
/// "Chia sẻ nhịp tim" trên vòng. Số rất to + vùng cường độ theo tuổi, đường nhịp 3 phút gần nhất,
/// thống kê phiên (thấp/cao/trung bình/thời lượng), ghi chú sự kiện ngay lúc đang đo.
/// T-022: khối **Thông tin vòng** — pin, tiếp xúc da, HRV trực tiếp (nếu vòng gửi RR), hãng/model,
/// danh sách dịch vụ Bluetooth vòng mở (vừa là tính năng, vừa để chẩn đoán vòng thật).
/// T-023: hàng Pin / Tiếp xúc da / HRV chỉ hiện khi vòng thật sự có; nút **Bài thở** (T-024: chọn 1 trong 7 bài);
/// tự lưu phiên đo (`LiveSession`) khi Dừng / đóng màn; lối vào **Các phiên đã đo**.
struct LiveHeartRateView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var monitor = LiveHeartRateMonitor()
    @State private var explaining: Metric?
    @State private var noteDraft: LiveNoteDraft?
    @State private var savedToast = false
    @State private var showingDeviceHelp = false
    @State private var showingBreath = false
    /// Phiên đo đã lưu (theo lúc bắt đầu) — tránh lưu trùng khi bấm Dừng rồi đóng màn.
    @State private var savedSessionStart: Date?

    /// Đường nhịp hiện bao nhiêu phút gần nhất.
    private let sparkMinutes: Double = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    statusCard
                    // Đã dừng / rớt kết nối vẫn giữ số cuối + thống kê phiên để anh xem lại.
                    if let bpm = monitor.bpm {
                        heroCard(bpm: bpm)
                        sparklineCard
                        sessionStats
                        if isLive { actionButtons(bpm: bpm) }
                        breathingEntry
                        deviceInfoCard
                    } else {
                        guideCard
                        breathingEntry
                        if hasDeviceInfo { deviceInfoCard }
                    }
                    sessionsLink
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xxl)
            }
            .defaultScrollAnchor(DebugOptions.scrollToBottom ? .bottom : .top)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Nhịp tim trực tiếp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HelpButton(title: "Nhịp tim trực tiếp") { explaining = .liveHeartRate }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { monitor.start() }
            .task {
                // Cờ chụp màn hình: mở bài thở sau khi màn này hiện xong (sheet lồng sheet cần chờ).
                guard DebugOptions.showBreath else { return }
                try? await Task.sleep(for: .seconds(1.5))
                showingBreath = true
            }
            .onDisappear {
                // Đóng màn khi đã đo ≥ 30 giây → tự lưu phiên.
                saveMeasureSession(minSeconds: 30)
                monitor.stop()
            }
            .sheet(item: $explaining) { metric in
                ExplanationSheet(metric: metric, value: monitor.bpm.map { "\($0)" } ?? "—",
                                 level: currentZone?.level ?? .unknown,
                                 todayNote: explainNote)
            }
            .sheet(item: $noteDraft) { draft in
                LiveNoteEditor(draft: draft) { note in
                    context.insert(HeartEvent(time: draft.time, note: note, bpm: Double(draft.bpm)))
                    savedToast = true
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingBreath) {
                // Dùng chung monitor đang chạy — không tạo kết nối mới.
                BreathingSessionView(monitor: monitor, autoStart: DebugOptions.showBreath)
            }
            .sheet(isPresented: $showingDeviceHelp) {
                DeviceInfoHelpSheet()
                    .presentationDetents([.medium, .large])
            }
            .overlay(alignment: .bottom) {
                if savedToast {
                    Label("Đã lưu ghi chú", systemImage: "checkmark.circle.fill")
                        .font(.label)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.good, in: Capsule())
                        .padding(.bottom, 24)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { savedToast = false }
                        }
                }
            }
            .animation(.easeInOut, value: savedToast)
        }
    }

    // MARK: - Trạng thái

    /// Đang nhận số (đã kết nối).
    private var isLive: Bool {
        if case .connected = monitor.state { return true }
        return false
    }

    private var currentZone: LiveHeartZone? {
        monitor.bpm.map { Thresholds.liveHeartRateZone(bpm: $0) }
    }

    private var statusInfo: (text: String, symbol: String, tint: Color) {
        switch monitor.state {
        case .idle: return ("Đã dừng đo", "pause.circle.fill", Theme.neutral)
        case .bluetoothOff: return ("Bluetooth đang tắt", "antenna.radiowaves.left.and.right.slash", Theme.caution)
        case .unauthorized: return ("Chưa cấp quyền Bluetooth", "lock.fill", Theme.caution)
        case .scanning: return ("Đang tìm vòng…", "magnifyingglass", Theme.brand)
        case .connecting(let n): return ("Đang kết nối với \(n)…", "arrow.triangle.2.circlepath", Theme.brand)
        case .connected(let n): return ("Đã kết nối với \(n)", "checkmark.circle.fill", Theme.good)
        case .disconnected: return ("Mất kết nối với vòng", "exclamationmark.triangle.fill", Theme.improve)
        case .unavailable: return ("Máy này không hỗ trợ Bluetooth", "xmark.octagon.fill", Theme.neutral)
        }
    }

    private var statusCard: some View {
        let info = statusInfo
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if case .scanning = monitor.state {
                    ProgressView().controlSize(.regular).frame(width: 34, height: 34)
                } else if case .connecting = monitor.state {
                    ProgressView().controlSize(.regular).frame(width: 34, height: 34)
                } else {
                    IconBadge(symbol: info.symbol, tint: info.tint, size: 34)
                }
                Text(info.text)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if isLive {
                    // Chấm "đang đo" nhấp nháy theo mỗi số mới.
                    Circle().fill(Theme.heart).frame(width: 10, height: 10)
                        .opacity(pulse ? 1 : 0.35)
                        .animation(.easeOut(duration: 0.5), value: monitor.lastUpdate)
                }
            }
            switch monitor.state {
            case .bluetoothOff:
                Text("Mở Trung tâm điều khiển và bật Bluetooth, rồi bấm Thử lại.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                wideButton("Thử lại", symbol: "arrow.clockwise", prominent: true) { monitor.retry() }
            case .unauthorized:
                Text("Vào Cài đặt → BBHealth → bật Bluetooth để app đọc nhịp tim từ vòng.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                wideButton("Mở Cài đặt", symbol: "gearshape.fill", prominent: true) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            case .disconnected:
                Text("Vòng ở xa điện thoại hoặc đã tắt Chia sẻ nhịp tim.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                wideButton("Thử lại", symbol: "arrow.clockwise", prominent: true) { monitor.retry() }
            case .idle:
                wideButton("Đo lại", symbol: "play.fill", prominent: true) { monitor.start() }
            default:
                EmptyView()
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: info.tint, radius: 20)
    }

    /// Nhấp nháy: giây chẵn/lẻ theo lần cập nhật cuối.
    private var pulse: Bool {
        guard let t = monitor.lastUpdate else { return false }
        return Int(t.timeIntervalSince1970) % 2 == 0
    }

    // MARK: - Hướng dẫn (chưa có số)

    private var guideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text("Cách bật").font(.cardTitle)
            } icon: {
                Image(systemName: "applewatch.radiowaves.left.and.right")
            }
            .foregroundStyle(Theme.heart)
            (Text("Trên vòng Fitbit Air: mở ")
             + Text("Share heart rate / Chia sẻ nhịp tim").bold()
             + Text(" rồi để vòng gần điện thoại."))
                .font(.body).foregroundStyle(Theme.textPrimary).lineSpacing(3)
            Text("App sẽ tự tìm và kết nối. Số nhịp tim cập nhật khoảng mỗi giây; đóng màn này là app ngừng đo.")
                .font(.callout).foregroundStyle(Theme.textSecondary).lineSpacing(2)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.heart, radius: 20)
    }

    // MARK: - Số to + vùng cường độ

    private func heroCard(bpm: Int) -> some View {
        let zone = Thresholds.liveHeartRateZone(bpm: bpm)
        return VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(Theme.heart)
                    .scaleEffect(pulse ? 1.0 : 0.88)
                    .animation(.easeOut(duration: 0.4), value: monitor.lastUpdate)
                Text("\(bpm)")
                    .font(.number(104))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText(value: Double(bpm)))
                    .animation(.snappy, value: bpm)
                Text("lần/phút")
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                Circle().fill(zone.color).frame(width: 9, height: 9)
                Text(zone.label)
            }
            .font(.system(.title3, design: .rounded).weight(.bold))
            .foregroundStyle(zone.color)
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(zone.color.opacity(0.15), in: Capsule())

            Text(zone.note)
                .font(.callout).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            zoneScale(current: zone)
        }
        .padding(Theme.Space.l + 2)
        .frame(maxWidth: .infinity)
        .card(tint: zone.color)
    }

    /// Thang 5 vùng, tô đậm vùng hiện tại.
    private func zoneScale(current: LiveHeartZone) -> some View {
        HStack(spacing: 4) {
            ForEach(LiveHeartZone.allCases) { z in
                VStack(spacing: 3) {
                    Capsule().fill(z.color.opacity(z == current ? 1 : 0.3)).frame(height: 7)
                    Text(z.label)
                        .font(.system(.caption2, design: .rounded).weight(z == current ? .bold : .medium))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(z == current ? z.color : Theme.textSecondary)
                    Text(z.bpmRangeText())
                        .font(.system(.caption2, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Đường nhịp vài phút gần nhất

    private var recentSamples: [LiveHeartRateMonitor.Sample] {
        guard let last = monitor.samples.last?.time else { return [] }
        let cutoff = last.addingTimeInterval(-sparkMinutes * 60)
        return monitor.samples.filter { $0.time >= cutoff }
    }

    private var sparklineCard: some View {
        let pts = recentSamples
        let lo = (pts.map(\.bpm).min() ?? 60) - 5
        let hi = (pts.map(\.bpm).max() ?? 80) + 5
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(Int(sparkMinutes)) phút gần nhất")
                .font(.cardTitle).foregroundStyle(Theme.textPrimary)
            Chart(pts) { p in
                AreaMark(x: .value("Giờ", p.time),
                         yStart: .value("Đáy", lo),
                         yEnd: .value("Nhịp", p.bpm))
                    .foregroundStyle(LinearGradient(colors: [Theme.heart.opacity(0.25), Theme.heart.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Giờ", p.time), y: .value("Nhịp", p.bpm))
                    .foregroundStyle(Theme.heart)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .stride(by: .minute)) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel()
                }
            }
            .frame(height: 130)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 20)
    }

    // MARK: - Số liệu phiên

    private var sessionStats: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Phiên đo này").font(.cardTitle).foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                statTile("Thấp nhất", monitor.sessionMin.map(String.init) ?? "—")
                statTile("Cao nhất", monitor.sessionMax.map(String.init) ?? "—")
                statTile("Trung bình", monitor.sessionAverage.map(String.init) ?? "—")
                statTile("Thời gian", durationText)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 20)
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.number(22))
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(Theme.textPrimary)
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    /// Thời lượng phiên "m:ss" (hoặc "h:mm:ss").
    private var durationText: String {
        guard let s = monitor.sessionStart, let e = monitor.lastUpdate else { return "—" }
        let total = max(0, Int(e.timeIntervalSince(s)))
        let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: - Nút hành động

    private func actionButtons(bpm: Int) -> some View {
        VStack(spacing: 10) {
            wideButton("Ghi chú sự kiện", symbol: "note.text.badge.plus", prominent: true) {
                noteDraft = LiveNoteDraft(time: Date(), bpm: bpm)
            }
            wideButton("Dừng", symbol: "stop.fill", prominent: false) {
                monitor.stop()
                saveMeasureSession(minSeconds: 10)
            }
        }
    }

    // MARK: - Lưu phiên đo (T-023)

    /// Lưu 1 `LiveSession` loại "đo" từ thống kê cả phiên của monitor (mỗi phiên lưu 1 lần).
    private func saveMeasureSession(minSeconds: TimeInterval) {
        guard let start = monitor.sessionStart, let end = monitor.lastUpdate,
              start != savedSessionStart,
              end.timeIntervalSince(start) >= minSeconds,
              let lo = monitor.sessionMin, let hi = monitor.sessionMax, let avg = monitor.sessionAverage
        else { return }
        context.insert(LiveSession(start: start, end: end, minBpm: lo, maxBpm: hi, avgBpm: avg,
                                   sampleCount: monitor.sessionSampleCount, kind: LiveSession.Kind.measure))
        try? context.save()
        savedSessionStart = start
    }

    // MARK: - Bài thở + Các phiên đã đo (T-023)

    private var breathingEntry: some View {
        let ready = isLive && monitor.bpm != nil
        return VStack(alignment: .leading, spacing: 10) {
            Button { showingBreath = true } label: {
                Label("Bài thở", systemImage: "wind")
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.breath)
            .disabled(!ready)
            Text(ready
                 ? "7 bài thở chậm có cơ sở khoa học — chọn theo lúc: trước khi ngủ, khi hồi hộp, khi ợ nóng… Xem nhịp tim hạ ngay trên màn."
                 : "Cần kết nối vòng và có số nhịp tim trước khi bắt đầu bài thở.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sessionsLink: some View {
        NavigationLink {
            LiveSessionsView()
        } label: {
            HStack(spacing: 12) {
                IconBadge(symbol: "list.bullet.rectangle.fill", tint: Theme.brand, size: 34)
                Text("Các phiên đã đo")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(radius: 20)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func wideButton(_ title: String, symbol: String, prominent: Bool,
                            action: @escaping () -> Void) -> some View {
        let label = Label(title, systemImage: symbol)
            .font(.system(.headline, design: .rounded))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        if prominent {
            Button(action: action) { label }.buttonStyle(.borderedProminent).tint(Theme.heart)
        } else {
            Button(action: action) { label }.buttonStyle(.bordered).tint(Theme.textSecondary)
        }
    }

    // MARK: - Thông tin vòng (T-022)

    /// Đã có gì đó để hiện ở khối Thông tin vòng (khi chưa có số nhịp tim).
    private var hasDeviceInfo: Bool {
        monitor.infoReading || monitor.discoveredServices != nil || monitor.batteryPercent != nil
    }

    /// Đang kết nối/đã kết nối mà mục chưa đọc xong → "đang đọc…".
    private var stillReading: Bool {
        switch monitor.state {
        case .connected, .connecting: return monitor.infoReading
        default: return false
        }
    }

    private var deviceInfoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Label {
                    Text("Thông tin vòng").font(.cardTitle)
                } icon: {
                    Image(systemName: "applewatch")
                }
                .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                HelpButton(title: "Thông tin vòng") { showingDeviceHelp = true }
            }
            // T-023: chỉ hiện các hàng vòng thật sự có — Fitbit Air chỉ mở nhịp tim + thông tin thiết bị.
            let rows = optionalRows
            ForEach(Array(rows.enumerated()), id: \.element) { i, row in
                if i > 0 { Divider().overlay(Theme.hairline) }
                switch row {
                case .battery: batteryRow
                case .contact: contactRow
                case .hrv: hrvRow
                }
            }
            if hasDeviceDetails || stillReading {
                if !rows.isEmpty { Divider().overlay(Theme.hairline) }
                deviceRow
            }
            if rows.isEmpty && monitor.measurementSeen && !stillReading {
                Text("Vòng này chỉ chia sẻ nhịp tim và thông tin thiết bị qua Bluetooth.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let services = monitor.discoveredServices {
                Divider().overlay(Theme.hairline)
                servicesGroup(services)
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 20)
    }

    private enum OptionalRow: Hashable { case battery, contact, hrv }

    /// Các hàng chỉ hiện khi vòng có: pin, tiếp xúc da, HRV trực tiếp (RR).
    private var optionalRows: [OptionalRow] {
        var r: [OptionalRow] = []
        if monitor.batteryPercent != nil { r.append(.battery) }
        if monitor.contactSupported { r.append(.contact) }
        if monitor.rrPresent { r.append(.hrv) }
        return r
    }

    /// Một hàng: icon + tiêu đề + nội dung tuỳ ý.
    private func infoRow<Content: View>(_ title: String, symbol: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol: symbol, tint: tint, size: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                content()
            }
            Spacer(minLength: 0)
        }
    }

    private var readingText: some View {
        Text("đang đọc…").font(.body).foregroundStyle(Theme.textTertiary)
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded).weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(tint.opacity(0.15), in: Capsule())
    }

    // Pin
    private var batteryRow: some View {
        let pct = monitor.batteryPercent
        let tint: Color = {
            guard let pct else { return Theme.neutral }
            return pct >= 50 ? Theme.good : (pct >= 20 ? Theme.caution : Theme.improve)
        }()
        return infoRow("Pin vòng", symbol: Self.batterySymbol(pct), tint: tint) {
            if let pct {
                HStack(spacing: 8) {
                    Text("\(pct)%")
                        .font(.number(26)).monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    chip(pct >= 50 ? "Còn nhiều" : (pct >= 20 ? "Vừa phải" : "Sắp hết"), tint: tint)
                }
                if pct < 20 {
                    Text("Nên sạc trước khi ngủ để không mất dữ liệu giấc ngủ.")
                        .font(.callout).foregroundStyle(Theme.improve)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if stillReading {
                readingText
            } else {
                Text("Vòng không chia sẻ mức pin")
                    .font(.body).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private static func batterySymbol(_ pct: Int?) -> String {
        guard let pct else { return "battery.0percent" }
        switch pct {
        case 75...: return "battery.100percent"
        case 50..<75: return "battery.75percent"
        case 20..<50: return "battery.50percent"
        default: return "battery.25percent"
        }
    }

    // Tiếp xúc da
    private var contactRow: some View {
        let seen = monitor.measurementSeen
        let detected = monitor.contactDetected
        let tint: Color = !seen || !monitor.contactSupported ? Theme.neutral
            : (detected == true ? Theme.good : Theme.improve)
        return infoRow("Tiếp xúc da", symbol: "hand.raised.fill", tint: tint) {
            if !seen {
                if isLive || stillReading { readingText }
                else { Text("Chưa có số").font(.body).foregroundStyle(Theme.textSecondary) }
            } else if !monitor.contactSupported {
                Text("Vòng không báo").font(.body).foregroundStyle(Theme.textSecondary)
            } else if detected == true {
                chip("Đang chạm da", tint: Theme.good)
            } else {
                chip("Vòng lỏng, chưa chạm da", tint: Theme.improve)
                Text("Đeo chặt hơn một chút, mặt cảm biến áp sát da phía trên xương cổ tay.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // HRV trực tiếp
    private var hrvRow: some View {
        infoRow("HRV trực tiếp", symbol: "waveform.path.ecg", tint: Theme.hrv) {
            if monitor.rrPresent {
                if let v = monitor.liveRMSSD {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(v.rounded()))")
                            .font(.number(26)).monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .contentTransition(.numericText(value: v))
                            .animation(.snappy, value: Int(v.rounded()))
                        Text("mili giây").font(.callout).foregroundStyle(Theme.textSecondary)
                    }
                    if monitor.rmssdHistory.count >= 2 { hrvSparkline }
                } else {
                    Text("Đang gom khoảng nhịp… (cần khoảng 1 phút)")
                        .font(.body).foregroundStyle(Theme.textTertiary)
                }
                Text("Cao hơn = cơ thể đang thư giãn hơn. Dùng để xem hơi thở chậm có giúp anh dịu lại không.")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !monitor.measurementSeen && (isLive || stillReading) {
                readingText
            } else {
                Text("Vòng không gửi khoảng nhịp (RR) → chưa tính được HRV trực tiếp")
                    .font(.body).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Đường HRV 2 phút gần nhất (nhỏ, không trục).
    private var hrvSparkline: some View {
        let pts = monitor.rmssdHistory
        let lo = (pts.map(\.rmssd).min() ?? 30) - 5
        let hi = (pts.map(\.rmssd).max() ?? 60) + 5
        return Chart(pts) { p in
            LineMark(x: .value("Giờ", p.time), y: .value("HRV", p.rmssd))
                .foregroundStyle(Theme.hrv)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: max(0, lo)...hi)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 44)
        .accessibilityLabel("Đường HRV 2 phút gần nhất")
    }

    // Thiết bị
    private var hasDeviceDetails: Bool {
        monitor.deviceName != nil || monitor.manufacturer != nil || monitor.model != nil || monitor.firmware != nil
            || monitor.hardware != nil || monitor.sensorLocation != nil
    }

    private var deviceRow: some View {
        infoRow("Thiết bị", symbol: "info.circle.fill", tint: Theme.brand) {
            VStack(alignment: .leading, spacing: 3) {
                if let n = monitor.deviceName {
                    Text(n)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                }
                if let v = monitor.manufacturer { detailLine("Hãng", v) }
                if let v = monitor.model {
                    // Model là mã số (vd "67") → "Mã mẫu"; tên chữ → "Mẫu".
                    detailLine(v.allSatisfy(\.isNumber) ? "Mã mẫu" : "Mẫu", v)
                }
                if let v = monitor.firmware { detailLine("Phần mềm vòng", v) }
                if let v = monitor.hardware { detailLine("Phần cứng", v) }
                if let v = monitor.sensorLocation { detailLine("Vị trí cảm biến", v) }
                if stillReading { readingText }
            }
        }
    }

    private func detailLine(_ label: String, _ value: String) -> some View {
        (Text(label + ": ").foregroundStyle(Theme.textSecondary)
         + Text(value).foregroundStyle(Theme.textPrimary).bold())
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    // Dịch vụ vòng mở (gấp lại cho màn gọn)
    private func servicesGroup(_ services: [LiveHeartRateMonitor.ServiceInfo]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                if services.isEmpty {
                    Text("Vòng không mở dịch vụ nào.").font(.callout).foregroundStyle(Theme.textSecondary)
                }
                ForEach(services) { s in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(s.name).font(.callout).foregroundStyle(Theme.textPrimary)
                        Spacer(minLength: 8)
                        Text(s.uuid)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Dịch vụ vòng mở (\(services.count))")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .tint(Theme.brand)
    }

    // MARK: - Nội dung sheet "?"

    private var explainNote: String {
        guard let bpm = monitor.bpm, let zone = currentZone else {
            return "Chưa nhận được số từ vòng. Bật Chia sẻ nhịp tim trên vòng và để gần điện thoại."
        }
        var s = "Lúc này tim anh \(bpm) lần/phút — vùng \(zone.label.lowercased()). \(zone.note)"
        if let lo = monitor.sessionMin, let hi = monitor.sessionMax {
            s += " Trong phiên đo: thấp nhất \(lo), cao nhất \(hi)."
        }
        s += "\n\nCác vùng theo tuổi 36 (tối đa ≈ 184): "
        s += LiveHeartZone.allCases.map { "\($0.label) \($0.bpmRangeText())" }.joined(separator: " · ")
        s += "."
        return s
    }
}

// MARK: - Ghi chú sự kiện nhanh

struct LiveNoteDraft: Identifiable {
    let id = UUID()
    let time: Date
    let bpm: Int
}

/// Sheet nhập ngắn "lúc này có chuyện gì" — lưu thành `HeartEvent` (hiện ở Nhịp tim → Ghi chú).
private struct LiveNoteEditor: View {
    let draft: LiveNoteDraft
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @FocusState private var focused: Bool

    private let suggestions = ["Đi bộ", "Tập thể dục", "Uống cà phê", "Họp căng thẳng", "Hồi hộp", "Nghỉ ngơi"]

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack(spacing: 10) {
                        IconBadge(symbol: "heart.fill", tint: Theme.heart, size: 42)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(TodayViewModel.time(draft.time))
                                .font(.number(26)).foregroundStyle(Theme.textPrimary)
                            Text("\(draft.bpm) lần/phút").font(.callout).foregroundStyle(Theme.heart)
                        }
                        Spacer()
                    }
                    .padding(Theme.Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(tint: Theme.heart)

                    Text("Lúc này có chuyện gì?").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    TextField("Vd: đi bộ nhanh, uống cà phê…", text: $note, axis: .vertical)
                        .font(.body)
                        .lineLimit(2...4)
                        .focused($focused)
                        .padding(12)
                        .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.Radius.small))

                    let cols = [GridItem(.adaptive(minimum: 100), spacing: 8)]
                    LazyVGrid(columns: cols, alignment: .leading, spacing: 8) {
                        ForEach(suggestions, id: \.self) { item in
                            Button { note = item } label: {
                                Text(item).font(.system(.subheadline, design: .rounded).weight(.medium))
                                    .foregroundStyle(Theme.brand)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(Theme.brand.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, Theme.Space.l)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Ghi chú sự kiện")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Huỷ") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Lưu") { onSave(trimmed); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Giải thích khối Thông tin vòng

/// Sheet "?" ngắn: đây là dữ liệu chuẩn Bluetooth, khác dữ liệu riêng của Fitbit.
private struct DeviceInfoHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    Text("Đây là những gì vòng **tự chia sẻ qua Bluetooth chuẩn** khi anh bật Chia sẻ nhịp tim: nhịp tim, có khi kèm pin, tên hãng, vòng có chạm da không, và khoảng cách giữa các nhịp (RR).")
                    Text("Nó **khác** dữ liệu riêng của Fitbit (giấc ngủ, điểm sẵn sàng, SpO₂…) — phần đó vòng chỉ gửi cho app Fitbit/Google rồi mới sang Apple Health. Vòng không mở mục nào (vd pin) thì app ẩn mục đó — không phải lỗi.")
                    Text("**HRV trực tiếp** chỉ tính được khi vòng gửi RR. Số cao hơn nghĩa là cơ thể đang thư giãn hơn; dao động theo từng phút là bình thường.")
                    Text("Gợi ý: nếu có gì lạ, anh chụp màn này (mở cả mục Dịch vụ vòng mở) gửi em để kiểm tra.")
                        .foregroundStyle(Theme.textSecondary)
                }
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
                .lineSpacing(3)
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, Theme.Space.l)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Thông tin vòng")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }
}

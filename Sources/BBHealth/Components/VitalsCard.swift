import SwiftUI

/// T-020 — Thẻ gộp "Sinh hiệu & vận động" ở màn Hôm nay (các chỉ số Google Health có mà app còn thiếu):
/// hai nhóm nhỏ, mỗi nhóm lưới 2 cột các ô nhỏ —
/// · **Lúc ngủ đêm qua**: Nhịp thở, Oxy máu.
/// · **Hôm nay**: Nhịp tim trong ngày (thấp–cao), Giờ vận động (x/9), Quãng đường, Calo vận động.
/// Ô nào nguồn không có số thì ẩn; nhóm không còn ô nào thì ẩn cả nhóm (TodayView ẩn cả thẻ khi trống).
struct VitalsCard: View {
    let model: TodayViewModel
    let onExplain: (Metric) -> Void
    var onOpenHeart: (() -> Void)?

    private let columns = [GridItem(.flexible(), spacing: Theme.Space.s),
                           GridItem(.flexible(), spacing: Theme.Space.s)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: 10) {
                IconBadge(symbol: "waveform.path.ecg.rectangle.fill", tint: Theme.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Sinh hiệu & vận động")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Chạm \"?\" để hiểu từng số")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            if model.respiratoryRate != nil || model.oxygenSaturation != nil {
                groupLabel("Lúc ngủ đêm qua", symbol: "moon.fill")
                LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                    if model.respiratoryRate != nil {
                        VitalTile(metric: .respiratoryRate, value: model.respiratoryValueText,
                                  level: model.respiratoryLevel, caption: "Bình thường 12–20",
                                  onExplain: { onExplain(.respiratoryRate) })
                    }
                    if model.oxygenSaturation != nil {
                        VitalTile(metric: .oxygenSaturation, value: model.oxygenValueText,
                                  level: model.oxygenLevel, caption: "Tốt từ 95% trở lên",
                                  onExplain: { onExplain(.oxygenSaturation) })
                    }
                }
            }

            if model.heartRange != nil || model.activeHours != nil
                || model.distanceKm != nil || model.activeEnergyKcal != nil {
                groupLabel("Hôm nay", symbol: "sun.max.fill")
                LazyVGrid(columns: columns, spacing: Theme.Space.s) {
                    if model.heartRange != nil {
                        VitalTile(metric: .heartRateRange, value: model.heartRangeValueText,
                                  level: model.heartRangeLevel, caption: "Thấp nhất – cao nhất · chạm xem",
                                  onExplain: { onExplain(.heartRateRange) })
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenHeart?() }
                    }
                    if let h = model.activeHours {
                        VitalTile(metric: .activeHours, value: "\(h)",
                                  level: model.activeHoursLevel, caption: "Giờ có ≥ 250 bước",
                                  onExplain: { onExplain(.activeHours) }) {
                            HourStrip(hourly: model.hourlySteps)
                        }
                    }
                    if model.distanceKm != nil {
                        VitalTile(metric: .distance, value: model.distanceValueText,
                                  level: model.distanceLevel, caption: "Đủ khi ≥ 3 km",
                                  onExplain: { onExplain(.distance) })
                    }
                    if model.activeEnergyKcal != nil {
                        VitalTile(metric: .activeEnergy, value: model.activeEnergyValueText,
                                  level: .unknown, showChip: false,
                                  caption: "Chỉ để tham khảo — ăn đủ quan trọng hơn",
                                  onExplain: { onExplain(.activeEnergy) })
                    }
                }
            }
        }
        .padding(Theme.Space.l)
        .card(tint: Theme.brand)
    }

    private func groupLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.system(.subheadline, design: .rounded).weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 2)
    }
}

/// Ô nhỏ trong thẻ Sinh hiệu: tên + "?" · số to + đơn vị · (phụ kiện) · chip màu ngưỡng + chú thích.
struct VitalTile<Accessory: View>: View {
    let metric: Metric
    let value: String
    let level: MetricLevel
    var showChip = true
    let caption: String
    let onExplain: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(metric.tint)
                Text(metric.title)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                HelpButton(title: metric.title, action: onExplain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.number(28))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(metric.unit)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            accessory
            Spacer(minLength: 0)
            if showChip { StatusChip(level: level, compact: true) }
            Text(caption)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Theme.surface.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
            .strokeBorder(metric.tint.opacity(0.18), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

extension VitalTile where Accessory == EmptyView {
    init(metric: Metric, value: String, level: MetricLevel, showChip: Bool = true,
         caption: String, onExplain: @escaping () -> Void) {
        self.init(metric: metric, value: value, level: level, showChip: showChip,
                  caption: caption, onExplain: onExplain) { EmptyView() }
    }
}

/// Dải 24 vạch nhỏ (0h–23h): vạch đậm = giờ đó có ≥ 250 bước — xem nhanh anh vận động rải đều chưa.
struct HourStrip: View {
    let hourly: [(hour: Int, steps: Int)]

    var body: some View {
        let active = Set(hourly.filter { $0.steps >= ActiveHours.stepsPerHour }.map(\.hour))
        HStack(spacing: 1.5) {
            ForEach(0..<24, id: \.self) { h in
                Capsule()
                    .fill(active.contains(h) ? Theme.brand : Theme.surfaceMuted)
                    .frame(height: active.contains(h) ? 12 : 6)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 12, alignment: .bottom)
        .accessibilityLabel("\(active.count) giờ có vận động")
    }
}

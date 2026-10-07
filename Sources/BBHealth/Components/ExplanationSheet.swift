import SwiftUI

/// Sheet giải thích một chỉ số: "Chỉ số này là gì" · "Của anh hôm nay" · "BS dặn" · "Gợi ý".
struct ExplanationSheet: View {
    let metric: Metric
    let value: String
    let level: MetricLevel
    let todayNote: String
    @Environment(\.dismiss) private var dismiss

    private var explanation: Explanation { Explanations.explanation(for: metric) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    hero
                    section(title: "Chỉ số này là gì", symbol: "info.circle.fill", tint: Theme.brand) {
                        Text(explanation.plain)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(3)
                    }
                    section(title: "Của anh hôm nay", symbol: "person.crop.circle.fill", tint: metric.tint) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(todayNote)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .lineSpacing(3)
                            if !Thresholds.bands(for: metric).isEmpty { bands }
                        }
                    }
                    if let note = explanation.doctorNote {
                        section(title: "BS dặn", symbol: "stethoscope", tint: Theme.improve) {
                            Text(note)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .lineSpacing(3)
                        }
                    }
                    section(title: "Gợi ý", symbol: "lightbulb.fill", tint: Theme.caution) {
                        Text(explanation.tip)
                            .font(.body)
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(3)
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconBadge(symbol: metric.symbol, tint: metric.tint, size: 46)
                Text(metric.title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.number(46))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(metric.unit)
                    .font(.system(.title3, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                // Calo vận động không chấm tốt/xấu (anh thiếu cân) → không hiện chip.
                if metric != .activeEnergy { StatusChip(level: level) }
            }
        }
        .padding(Theme.Space.l + 2)
        .card(tint: metric.tint)
        .padding(.top, Theme.Space.s)
    }

    private var bands: some View {
        HStack(spacing: 6) {
            ForEach(Thresholds.bands(for: metric), id: \.range) { band in
                VStack(spacing: 3) {
                    Text(band.level.label)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(band.range)
                        .font(.system(.footnote, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(band.level.color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(band.level.color.opacity(band.level == level ? 0.2 : 0.08),
                            in: RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous))
                .overlay {
                    if band.level == level {
                        RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                            .strokeBorder(band.level.color.opacity(0.5), lineWidth: 1.5)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func section<Content: View>(title: String, symbol: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title).font(.cardTitle)
            } icon: {
                Image(systemName: symbol)
            }
            .foregroundStyle(tint)
            content()
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint, radius: 20)
    }
}

#Preview {
    ExplanationSheet(metric: .sleep, value: "5,4", level: .bad,
                     todayNote: "Đêm qua anh ngủ 5,4 giờ, thiếu 1,6 giờ so với mục tiêu 7 giờ.")
}

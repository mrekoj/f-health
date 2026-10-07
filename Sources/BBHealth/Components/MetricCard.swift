import SwiftUI

/// Đầu thẻ: icon tròn + nhãn (+ phụ đề) + chip trạng thái + nút "?".
struct MetricHeader: View {
    let metric: Metric
    var subtitle: String?
    let level: MetricLevel
    var showChip = true
    let onExplain: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol: metric.symbol, tint: metric.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(metric.title)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 4)
            if showChip { StatusChip(level: level) }
            HelpButton(title: metric.title, action: onExplain)
        }
    }
}

// MARK: - Thẻ lớn Giấc ngủ

struct SleepHeroCard: View {
    let model: TodayViewModel
    let onExplain: () -> Void
    var onOpenDetail: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            MetricHeader(metric: .sleep, subtitle: "Đêm qua", level: model.sleepLevel, onExplain: onExplain)

            HStack(spacing: Theme.Space.xl) {
                ZStack {
                    ProgressRing(progress: model.sleepProgress, tint: Theme.sleep, lineWidth: 13)
                    VStack(spacing: 0) {
                        Text(model.sleepValueText)
                            .font(.number(38))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("/ 7 giờ")
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .frame(width: 124, height: 124)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Ngủ \(model.sleepValueText) giờ trên mục tiêu 7 giờ")

                VStack(alignment: .leading, spacing: 12) {
                    timeRow(symbol: "moon.fill", label: "Đi ngủ", value: model.bedTimeText ?? "—")
                    timeRow(symbol: "sun.horizon.fill", label: "Thức dậy", value: model.wakeTimeText ?? "—")
                    timeRow(symbol: "eye.fill", label: "Thức giữa đêm",
                            value: model.sleep.map { "\($0.awakeCount) lần" } ?? "—")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if onOpenDetail != nil {
                HStack(spacing: 4) {
                    Text("Xem diễn biến & giai đoạn ngủ")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                    Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    Spacer()
                }
                .foregroundStyle(Theme.sleep)
            }
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.sleep)
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetail?() }
    }

    private func timeRow(symbol: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.sleep)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(value)
                    .font(.number(19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

// MARK: - Thẻ vừa (Nhịp tim, Bước chân)

struct CompactMetricCard<Accessory: View>: View {
    let metric: Metric
    let value: String
    let level: MetricLevel
    let caption: String
    let onExplain: () -> Void
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                IconBadge(symbol: metric.symbol, tint: metric.tint, size: 34)
                Spacer()
                HelpButton(title: metric.title, action: onExplain)
            }
            VStack(alignment: .leading, spacing: 0) {
            Text(metric.title)
                .font(.label)
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.number(32))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(metric.unit)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            }
            accessory
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                StatusChip(level: level, compact: true)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 2)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(tint: metric.tint)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Thẻ Cân nặng (rộng)

struct WeightCard: View {
    let model: TodayViewModel
    let onExplain: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MetricHeader(metric: .bodyMass, subtitle: model.bodyMassDetailText,
                         level: model.bodyMassLevel, onExplain: onExplain)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(model.bodyMassValueText)
                    .font(.number(34))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("kg")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if let goal = model.weightGoalText {
                    Text(goal)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.weight)
                        .multilineTextAlignment(.trailing)
                }
            }

            VStack(spacing: 6) {
                ProgressBar(progress: model.weightProgress, tint: Theme.weight, height: 10)
                HStack {
                    Text(TodayViewModel.decimal(Thresholds.weightGoalKg - 8, digits: 0) + " kg")
                    Spacer()
                    Text(Thresholds.weightGoalText)
                }
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.weight)
    }
}

// MARK: - Bữa tiếp theo

struct NextMealCard: View {
    let date: Date

    var body: some View {
        let next = MealPlan.nextMeal(at: date)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(symbol: next.meal.symbol, tint: Theme.meal)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bữa tiếp theo")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(next.meal.name)
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(next.tomorrow ? "Sáng mai \(next.meal.time)" : next.meal.time)
                        .font(.number(20, weight: .bold))
                        .foregroundStyle(Theme.meal)
                    Text(whenText(next))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(next.meal.options.prefix(3).enumerated()), id: \.offset) { idx, option in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(idx == 0 ? "Gợi ý" : "hoặc")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .foregroundStyle(idx == 0 ? Theme.meal : Theme.textTertiary)
                            .frame(width: 40, alignment: .leading)
                        Text(option)
                            .font(idx == 0 ? .callout.weight(.medium) : .callout)
                            .foregroundStyle(idx == 0 ? Theme.textPrimary : Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))

            HStack(spacing: 8) {
                TagChip(text: "~\(next.meal.kcal) kcal", symbol: "flame.fill", tint: Theme.meal)
                if let note = next.meal.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.meal)
    }

    private func whenText(_ n: (meal: Meal, isNow: Bool, minutesUntil: Int, tomorrow: Bool)) -> String {
        if n.isNow { return "Đến giờ ăn rồi" }
        let h = n.minutesUntil / 60, m = n.minutesUntil % 60
        if h == 0 { return "Còn \(m) phút" }
        if m == 0 { return "Còn \(h) giờ" }
        return "Còn \(h) giờ \(m) phút"
    }
}

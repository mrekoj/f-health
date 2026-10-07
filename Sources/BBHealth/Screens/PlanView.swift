import SwiftUI

/// Kế hoạch hôm nay: dòng thời gian 6 bữa, kiêng theo lời bác sĩ, giờ ngủ.
struct PlanView: View {
    @State private var now = DebugOptions.now

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    header
                    timeline
                    forbiddenBlock
                    sleepBlock
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .defaultScrollAnchor(DebugOptions.scrollToBottom ? .bottom : .top)
            .background(Theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { now = DebugOptions.now }
        }
    }

    // MARK: - Đầu trang

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ngày văn phòng")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.brand)
            Text("Kế hoạch hôm nay")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                TagChip(text: "6 bữa nhỏ", symbol: "fork.knife", tint: Theme.meal)
                TagChip(text: "~\(MealPlan.totalKcal) kcal", symbol: "flame.fill", tint: Theme.meal)
            }
            .padding(.top, 6)
            Text("Đủ để tăng 0,25–0,5 kg mỗi tuần.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, Theme.Space.l)
    }

    // MARK: - Dòng thời gian

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(MealPlan.officeDay.enumerated()), id: \.element.id) { idx, meal in
                MealTimelineRow(meal: meal,
                                status: MealPlan.status(of: meal, at: now),
                                isFirst: idx == 0,
                                isLast: idx == MealPlan.officeDay.count - 1)
            }
        }
    }

    // MARK: - Kiêng

    private var forbiddenBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(symbol: "stethoscope", tint: Theme.improve)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Kiêng theo lời bác sĩ")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Danh sách mẫu — sửa theo lời bác sĩ của bạn")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            FlowLayout(spacing: 8) {
                ForEach(MealPlan.forbidden, id: \.self) { item in
                    TagChip(text: item, symbol: "xmark", tint: Theme.improve)
                }
            }
            Text(MealPlan.forbiddenNote)
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.improve)
    }

    // MARK: - Giờ ngủ

    private var sleepBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(symbol: "moon.zzz.fill", tint: Theme.sleep)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Giờ ngủ")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Mục tiêu ≥ 7 giờ mỗi đêm")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            VStack(spacing: 0) {
                sleepRow("laptopcomputer", "Tắt máy tính, không dùng Awair", "22h00")
                Divider().overlay(Theme.hairline).padding(.leading, 40)
                sleepRow("bed.double.fill", "Lên giường", "22h30–23h")
                Divider().overlay(Theme.hairline).padding(.leading, 40)
                sleepRow("sun.horizon.fill", "Thức dậy", "6h30–7h")
            }
            .padding(.horizontal, 12)
            .background(Theme.surface.opacity(0.7),
                        in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .padding(Theme.Space.l + 2)
        .card(tint: Theme.sleep)
    }

    private func sleepRow(_ symbol: String, _ title: String, _ time: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.sleep)
                .frame(width: 28)
            Text(title)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 8)
            Text(time)
                .font(.number(17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Một dòng bữa ăn

private struct MealTimelineRow: View {
    let meal: Meal
    let status: MealPlan.MealStatus
    let isFirst: Bool
    let isLast: Bool

    private var isCurrent: Bool { status == .current }
    private var isPast: Bool { status == .past }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Cột giờ
            Text(meal.time)
                .font(.number(15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isCurrent ? Theme.meal : (isPast ? Theme.textTertiary : Theme.textSecondary))
                .lineLimit(1)
                .fixedSize()
                .frame(width: 50, alignment: .trailing)
                .padding(.top, 18)

            // Trục + chấm
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(isFirst ? .clear : Theme.hairline)
                        .frame(width: 2, height: 22)
                    Rectangle()
                        .fill(isLast ? .clear : Theme.hairline)
                        .frame(width: 2)
                }
                dot.padding(.top, 14)
            }
            .frame(width: 22)

            // Thẻ
            card
                .padding(.bottom, isLast ? 0 : 12)
        }
    }

    @ViewBuilder private var dot: some View {
        if isPast {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Theme.good.opacity(0.85), in: Circle())
        } else if isCurrent {
            Circle()
                .fill(Theme.meal)
                .frame(width: 14, height: 14)
                .padding(3)
                .background(Theme.meal.opacity(0.25), in: Circle())
        } else {
            Circle()
                .strokeBorder(Theme.textTertiary.opacity(0.6), lineWidth: 2)
                .background(Circle().fill(Theme.background))
                .frame(width: 16, height: 16)
                .padding(2)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: meal.symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isPast ? Theme.textTertiary : Theme.meal)
                Text(meal.name)
                    .font(.cardTitle)
                    .foregroundStyle(isPast ? Theme.textSecondary : Theme.textPrimary)
                Spacer(minLength: 4)
                if isCurrent {
                    Text("Sắp tới")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.meal, in: Capsule())
                } else if isPast {
                    Text("Đã qua")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            if !isPast || isCurrent {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(meal.options, id: \.self) { option in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("•").foregroundStyle(Theme.meal)
                            Text(option)
                                .foregroundStyle(Theme.textPrimary.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .font(.callout)
                if let note = meal.note {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(meal.options.first ?? "")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Text("~\(meal.kcal) kcal")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(isPast ? Theme.textTertiary : Theme.meal)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(MealCardStyle(isCurrent: isCurrent, isPast: isPast))
    }
}

private struct MealCardStyle: ViewModifier {
    let isCurrent: Bool
    let isPast: Bool

    func body(content: Content) -> some View {
        if isCurrent {
            content
                .card(tint: Theme.meal, radius: 18)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.meal.opacity(0.45), lineWidth: 1.5)
                }
        } else if isPast {
            content
                .background(Theme.surfaceMuted.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            content.card(radius: 18)
        }
    }
}

// MARK: - Bố cục chip tự xuống dòng

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    PlanView()
}

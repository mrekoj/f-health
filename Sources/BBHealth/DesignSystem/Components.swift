import SwiftUI

// MARK: - Nền thẻ nhuộm màu

/// Nền thẻ: bề mặt + nhuộm nhẹ theo màu, viền mảnh cùng tông, bóng đổ nhẹ.
struct CardBackground: ViewModifier {
    var tint: Color?
    var radius: CGFloat = Theme.Radius.card
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(Theme.surface)
                    if let tint {
                        shape.fill(
                            LinearGradient(colors: [tint.opacity(Theme.tintOpacity(scheme) * 1.5),
                                                    tint.opacity(Theme.tintOpacity(scheme) * 0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                    }
                }
                .shadow(color: Theme.shadow, radius: 14, x: 0, y: 6)
            }
            .overlay {
                shape.strokeBorder((tint ?? Theme.hairline).opacity(tint == nil ? 1 : 0.16), lineWidth: 1)
            }
    }
}

extension View {
    func card(tint: Color? = nil, radius: CGFloat = Theme.Radius.card) -> some View {
        modifier(CardBackground(tint: tint, radius: radius))
    }
}

// MARK: - Icon trong hình tròn

struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Chip trạng thái

struct StatusChip: View {
    let level: MetricLevel
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(level.color)
                .frame(width: 7, height: 7)
            Text(level.label)
                .lineLimit(1)
                .fixedSize()
        }
        .font(.system(compact ? .caption : .footnote, design: .rounded).weight(.semibold))
        .foregroundStyle(level.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(level.color.opacity(0.14), in: Capsule())
    }
}

/// Chip chung (nhãn + icon tuỳ chọn).
struct TagChip: View {
    let text: String
    var symbol: String?
    var tint: Color = Theme.brand

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.caption.weight(.bold))
            }
            Text(text).lineLimit(1)
        }
        .font(.system(.subheadline, design: .rounded).weight(.medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Nút "?"

struct HelpButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .background(Theme.surfaceMuted, in: Circle())
                .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Giải thích \(title)")
    }
}

// MARK: - Vòng tiến độ

struct ProgressRing: View {
    /// 0…1 (có thể > 1, sẽ cắt ở 1).
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.8), tint],
                                    center: .center,
                                    startAngle: .degrees(0),
                                    endAngle: .degrees(360 * max(0.001, min(progress, 1)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Thanh tiến độ

struct ProgressBar: View {
    let progress: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.7), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Tiêu đề khối

struct SectionHeader: View {
    let title: String
    var symbol: String?
    var tint: Color = Theme.brand
    var trailing: String?

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Trạng thái trống

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Theme.brand
    var features: [(String, String)] = []

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.08))
                    .frame(width: 168, height: 168)
                Circle()
                    .fill(tint.opacity(0.14))
                    .frame(width: 120, height: 120)
                Image(systemName: symbol)
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.bottom, 4)

            VStack(spacing: Theme.Space.s) {
                TagChip(text: "Sắp có", symbol: "sparkles", tint: tint)
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(message)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !features.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features, id: \.1) { item in
                        HStack(spacing: 12) {
                            IconBadge(symbol: item.0, tint: tint, size: 32)
                            Text(item.1)
                                .font(.callout)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(Theme.Space.l)
                .card(tint: tint, radius: 20)
            }
        }
        .padding(.horizontal, Theme.Space.xxl)
    }
}

// MARK: - Thang vùng (vị trí số hiện tại trên các vùng tốt/chú ý/cải thiện)

struct RangeBar: View {
    let value: Double?
    let range: ClosedRange<Double>
    /// Các mốc trên (tăng dần) kèm màu vùng kết thúc tại mốc đó.
    let stops: [(Double, Color)]
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let span = range.upperBound - range.lowerBound
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Array(stops.enumerated()), id: \.offset) { idx, stop in
                        let lower = idx == 0 ? range.lowerBound : stops[idx - 1].0
                        Capsule()
                            .fill(stop.1.opacity(0.35))
                            .frame(width: max(0, w * (stop.0 - lower) / span - 2))
                    }
                }
                if let value {
                    let x = w * (min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / span
                    Circle()
                        .fill(Theme.surface)
                        .overlay(Circle().strokeBorder(Theme.textPrimary.opacity(0.75), lineWidth: 2.5))
                        .frame(width: height + 8, height: height + 8)
                        .offset(x: x - (height + 8) / 2)
                }
            }
            .frame(height: geo.size.height)
        }
        .frame(height: height + 8)
    }
}

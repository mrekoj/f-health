import SwiftUI

/// Chip chất lượng giấc trưa (nhãn + chấm màu theo ngưỡng độ dài).
struct NapChip: View {
    let minutes: Int
    var compact = false

    private var level: MetricLevel { Explanations.napLevel(minutes: minutes) }
    private var text: String { Explanations.napQuality(minutes: minutes) }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(level.color).frame(width: 7, height: 7)
            Text(text).lineLimit(1).fixedSize()
        }
        .font(.system(compact ? .caption : .footnote, design: .rounded).weight(.semibold))
        .foregroundStyle(level.color)
        .padding(.horizontal, compact ? 8 : 10)
        .padding(.vertical, compact ? 4 : 5)
        .background(level.color.opacity(0.14), in: Capsule())
    }
}

/// Nhãn phụ "ước tính" (màu trung tính) cho giấc **suy ra từ nhịp tim** (Fitbit không ghi phiên ngủ) —
/// để phân biệt với giấc Fitbit ghi thật.
struct EstimatedTag: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "wand.and.stars").font(.caption2.weight(.bold))
            Text("ước tính")
        }
        .font(.system(.caption2, design: .rounded).weight(.semibold))
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.textSecondary.opacity(0.14), in: Capsule())
    }
}

/// Card "Giấc ngủ trưa" ở màn Hôm nay (dưới 4 ô chính). Có giấc → tóm tắt + giấc gần nhất;
/// không có → trạng thái trống **thành thật** (nêu rõ giới hạn thiết bị). Chạm để mở màn chi tiết.
struct NapCard: View {
    let model: TodayViewModel
    let onExplain: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconBadge(symbol: "powersleep", tint: Theme.sleep)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Giấc ngủ trưa").font(.cardTitle).foregroundStyle(Theme.textPrimary)
                    Text("Tự ghi nhận · hôm nay").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 4)
                HelpButton(title: "Giấc ngủ trưa", action: onExplain)
            }

            if model.hasNaps {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(model.napTotalMinutes)")
                        .font(.number(34)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    Text("phút").font(.system(.subheadline, design: .rounded).weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(model.napCount) giấc")
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .foregroundStyle(Theme.sleep)
                }

                if let nap = model.latestNap {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.fill")
                                .font(.footnote.weight(.semibold)).foregroundStyle(Theme.sleep).frame(width: 18)
                            Text("Gần nhất \(TodayViewModel.time(nap.start)) · \(nap.minutes) phút")
                                .font(.system(.subheadline, design: .rounded).weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer(minLength: 4)
                            NapChip(minutes: nap.minutes, compact: true)
                        }
                        if nap.estimated {
                            HStack(spacing: 6) {
                                EstimatedTag()
                                Text("suy từ nhịp tim — Fitbit không ghi giấc này")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.sleep.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }

                detailLink
            } else {
                Text("Hôm nay chưa ghi nhận giấc ngủ trưa nào. (App đọc phiên ngủ Fitbit và ước tính thêm từ nhịp tim; giấc quá ngắn hoặc nhịp tim không tụt hẳn vẫn có thể bỏ sót.)")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                detailLink
            }
        }
        .padding(Theme.Space.l + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.sleep)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }

    private var detailLink: some View {
        HStack(spacing: 4) {
            Text("Xem các giấc trưa & thống kê")
                .font(.system(.footnote, design: .rounded).weight(.semibold))
            Image(systemName: "chevron.right").font(.caption2.weight(.bold))
            Spacer()
        }
        .foregroundStyle(Theme.sleep)
    }
}

/// Sheet giải thích "Giấc ngủ trưa": là gì, giới hạn thiết bị, và lời khuyên gắn hồ sơ của bạn.
struct NapInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    section(title: "Giấc ngủ trưa là gì", symbol: "powersleep", tint: Theme.sleep) {
                        Text("Đây là những giấc ngủ ban ngày (ngủ trưa, chợp mắt) app tự đọc và tự đánh giá — anh không phải ghi tay. Một giấc trưa ngắn 10–20 phút giúp tỉnh táo buổi chiều mà không làm uể oải.")
                    }
                    section(title: "App bắt giấc trưa bằng hai cách", symbol: "sparkles", tint: Theme.sleep) {
                        Text("1) Đọc **phiên ngủ** mà vòng Fitbit ghi được (chính xác nhất).\n\n2) Khi Fitbit bỏ sót giấc ngắn, app **ước tính từ nhịp tim**: ban ngày nếu nhịp tim tụt về sát mức nghỉ và giữ yên hơn 10 phút thì coi là một giấc trưa. Giấc kiểu này có nhãn “ước tính” — giờ và độ dài chỉ gần đúng, không chính xác bằng phiên ngủ Fitbit.")
                    }
                    section(title: "Vì sao có lúc không thấy giấc nào", symbol: "exclamationmark.circle.fill", tint: Theme.caution) {
                        Text("App thấy giấc trưa khi Fitbit ghi được phiên ngủ, hoặc khi nhịp tim tụt rõ về mức nghỉ đủ lâu. Nếu anh chỉ chợp mắt rất ngắn mà nhịp tim không tụt hẳn thì cả hai cách đều có thể bỏ sót — đó là giới hạn của thiết bị, không phải lỗi.")
                    }
                    section(title: "Lời khuyên cho anh", symbol: "lightbulb.fill", tint: Theme.good) {
                        Text("Nếu ngủ đêm chưa ổn, giấc trưa tốt nhất là 10–20 phút và tránh ngủ trưa sau 15h, kẻo tối khó ngủ hơn. Giấc trưa quá 30 phút dễ làm dậy uể oải và ảnh hưởng giấc đêm.\n\nMàu chip: xanh = lý tưởng (10–25 phút), vàng = hơi ngắn/hơi dài, đỏ = giấc dài nên để ý.")
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.vertical, Theme.Space.l)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Giấc ngủ trưa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private func section<Content: View>(title: String, symbol: String, tint: Color,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label { Text(title).font(.cardTitle) } icon: { Image(systemName: symbol) }
                .foregroundStyle(tint)
            content()
                .font(.body).foregroundStyle(Theme.textPrimary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint, radius: 20)
    }
}

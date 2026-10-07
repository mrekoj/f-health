import SwiftUI
import SwiftData

/// Màn **Các phiên đã đo** (T-023): danh sách `LiveSession` (đo trực tiếp + bài thở), mới nhất trên đầu.
/// Mỗi dòng: ngày · giờ · loại · thấp–cao · trung bình · thời lượng (+ "82→68" với bài thở). Vuốt để xoá.
struct LiveSessionsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LiveSession.start, order: .reverse) private var sessions: [LiveSession]

    var body: some View {
        Group {
            if sessions.isEmpty {
                emptyView
            } else {
                List {
                    ForEach(sessions) { s in
                        LiveSessionRow(session: s)
                            .listRowBackground(Theme.surface)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(sessions[i]) }
                        try? context.save()
                    }
                    Section {
                        EmptyView()
                    } footer: {
                        Text("Vuốt sang trái để xoá một phiên. Phiên đo thường được lưu khi anh bấm Dừng hoặc đóng màn sau ít nhất 30 giây; bài thở được lưu khi kết thúc.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Các phiên đã đo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Space.l) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 50, weight: .semibold))
                .foregroundStyle(Theme.heart)
                .symbolRenderingMode(.hierarchical)
            Text("Chưa có phiên nào")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Đo nhịp tim trực tiếp rồi bấm Dừng, hoặc làm một bài thở — phiên sẽ được lưu ở đây để anh xem lại.")
                .font(.body).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LiveSessionRow: View {
    let session: LiveSession

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "vi_VN")
        f.dateFormat = "EEEE, d/M"
        return f
    }()
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private var tint: Color { session.isBreathing ? Theme.breath : Theme.heart }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                IconBadge(symbol: session.isBreathing ? "wind" : "heart.fill", tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.dayFormatter.string(from: session.start).capitalizedFirst)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(Self.timeFormatter.string(from: session.start)) · \(LiveSession.durationText(session.duration))")
                        .font(.callout).monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Text(session.isBreathing ? "Bài thở" : "Đo")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(tint.opacity(0.15), in: Capsule())
            }
            HStack(spacing: 14) {
                stat("Thấp–cao", "\(session.minBpm)–\(session.maxBpm)")
                stat("Trung bình", "\(session.avgBpm)")
                if session.isBreathing, let a = session.startBpm, let b = session.endBpm {
                    stat("Nhịp tim", "\(a)→\(b)", tint: b < a ? Theme.good : Theme.textPrimary)
                }
            }
            if session.isBreathing, !session.note.isEmpty {
                // T-024: ghi chú bài thở = "<tên bài> · N phút" → hiện rõ tên bài.
                Label(session.note, systemImage: "wind")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.breath)
            } else if !session.note.isEmpty {
                Text(session.note).font(.callout).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func stat(_ title: String, _ value: String, tint: Color = Theme.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.number(20)).monospacedDigit()
                .foregroundStyle(tint)
            Text(title)
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private extension String {
    /// "thứ bảy, 4/10" → "Thứ bảy, 4/10".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

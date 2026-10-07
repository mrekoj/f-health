import SwiftUI

/// Sheet giải thích tự do (không gắn một `Metric`): tiêu đề + các đoạn (tiêu đề nhỏ, icon, màu, nội dung).
/// Dùng cho nút "?" của màn Báo cáo, Hồ sơ, Trợ lý AI…
struct InfoSheet: View {
    struct Section: Identifiable {
        let title: String
        let symbol: String
        let tint: Color
        let text: String
        var id: String { title }
    }

    let title: String
    let symbol: String
    let tint: Color
    let sections: [Section]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: symbol, tint: tint, size: 48)
                        Text(title)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, Theme.Space.s)
                    ForEach(sections) { s in
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: s.title, symbol: s.symbol, tint: s.tint)
                            Text(s.text)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Theme.Space.l)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(tint: s.tint)
                    }
                }
                .padding(.horizontal, Theme.Space.page)
                .padding(.bottom, Theme.Space.xxl)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}

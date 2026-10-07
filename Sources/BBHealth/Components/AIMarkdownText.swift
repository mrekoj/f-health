import SwiftUI

/// Hiển thị chữ AI trả về (Markdown đơn giản): dòng **in đậm** đứng riêng = tiêu đề mục, "- " = gạch đầu
/// dòng, còn lại là đoạn văn; in đậm/nghiêng trong dòng giữ nguyên. Không cần thư viện ngoài.
struct AIMarkdownText: View {
    let text: String
    /// Chỉ hiện N dòng đầu (nil = hiện hết).
    var limit: Int? = nil

    private enum Line: Hashable {
        case heading(String), bullet(String), paragraph(String), gap
    }

    /// Số dòng hiển thị được (để biết có cần nút "Xem hết").
    var lineCount: Int { lines.count }

    private var lines: [Line] {
        var out: [Line] = []
        for raw in text.components(separatedBy: "\n") {
            var s = raw.trimmingCharacters(in: .whitespaces)
            if s.isEmpty { if out.last != .gap && !out.isEmpty { out.append(.gap) }; continue }
            while s.hasPrefix("#") { s.removeFirst() }
            s = s.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("- ") || s.hasPrefix("* ") || s.hasPrefix("• ") {
                out.append(.bullet(String(s.dropFirst(2))))
            } else if s.hasPrefix("**") && s.hasSuffix("**") && s.count > 4 && !s.dropFirst(2).dropLast(2).contains("**") {
                out.append(.heading(String(s.dropFirst(2).dropLast(2))))
            } else if raw.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                out.append(.heading(s))
            } else {
                out.append(.paragraph(s))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.prefix(limit ?? Int.max).enumerated()), id: \.offset) { _, line in
                switch line {
                case .heading(let s):
                    Text(inline(s))
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.top, 6)
                case .bullet(let s):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle().fill(Theme.brand).frame(width: 6, height: 6).offset(y: -2)
                        Text(inline(s)).font(.body).foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .paragraph(let s):
                    Text(inline(s)).font(.body).foregroundStyle(Theme.textPrimary)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                case .gap:
                    Color.clear.frame(height: 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}

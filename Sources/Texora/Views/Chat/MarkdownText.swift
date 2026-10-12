import SwiftUI

/// Lightweight Markdown renderer for chat replies: paragraphs, headings, lists, quotes and code blocks.
struct MarkdownText: View {
    @Environment(\.theme) private var theme
    let text: String
    var fontSize: CGFloat = 13.5

    enum Block: Hashable {
        case paragraph(String)
        case heading(Int, String)
        case bullet(String, Int)
        case numbered(String, String)
        case quote(String)
        case code(String, String)
        case rule
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(Self.parse(text).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block {
        case .paragraph(let s):
            inline(s).font(.system(size: fontSize)).foregroundStyle(theme.textColor)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        case .heading(let level, let s):
            inline(s).font(.system(size: fontSize + (level == 1 ? 4 : level == 2 ? 2 : 1), weight: .semibold))
                .foregroundStyle(theme.textColor).padding(.top, 4)
        case .bullet(let s, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("•").foregroundStyle(theme.mutedColor)
                inline(s).foregroundStyle(theme.textColor).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: fontSize))
            .padding(.leading, CGFloat(indent) * 14)
        case .numbered(let n, let s):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(n).foregroundStyle(theme.mutedColor).monospacedDigit()
                inline(s).foregroundStyle(theme.textColor).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: fontSize))
        case .quote(let s):
            HStack(spacing: 8) {
                Rectangle().fill(theme.borderColor).frame(width: 3)
                inline(s).font(.system(size: fontSize)).foregroundStyle(theme.secondaryColor)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let lang, let code):
            CodeBlock(language: lang, code: code, fontSize: fontSize - 1.5)
        case .rule:
            ThemedDivider().padding(.vertical, 4)
        }
    }

    private func inline(_ s: String) -> Text {
        if let attr = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            var a = attr
            for run in a.runs where run.inlinePresentationIntent?.contains(.code) == true {
                a[run.range].font = .system(size: fontSize - 1, design: .monospaced)
                a[run.range].foregroundColor = theme.accentColor
            }
            return Text(a)
        }
        return Text(s)
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var para: [String] = []
        var lines = text.components(separatedBy: "\n")[...]
        func flush() {
            if !para.isEmpty { blocks.append(.paragraph(para.joined(separator: "\n"))); para.removeAll() }
        }
        while let raw = lines.first {
            lines = lines.dropFirst()
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                flush()
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                while let l = lines.first {
                    lines = lines.dropFirst()
                    if l.trimmingCharacters(in: .whitespaces).hasPrefix("```") { break }
                    code.append(l)
                }
                blocks.append(.code(lang, code.joined(separator: "\n")))
            } else if line.isEmpty {
                flush()
            } else if line == "---" || line == "***" {
                flush(); blocks.append(.rule)
            } else if let m = line.firstMatch(of: #/^(#{1,4})\s+(.*)$/#) {
                flush(); blocks.append(.heading(m.1.count, String(m.2)))
            } else if let m = raw.firstMatch(of: #/^(\s*)[-*•]\s+(.*)$/#) {
                flush(); blocks.append(.bullet(String(m.2), m.1.count / 2))
            } else if let m = line.firstMatch(of: #/^(\d+[.)])\s+(.*)$/#) {
                flush(); blocks.append(.numbered(String(m.1), String(m.2)))
            } else if line.hasPrefix(">") {
                flush(); blocks.append(.quote(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))
            } else {
                para.append(raw)
            }
        }
        flush()
        return blocks
    }
}

struct CodeBlock: View {
    @Environment(\.theme) private var theme
    let language: String
    let code: String
    var fontSize: CGFloat = 12
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language.isEmpty ? "code" : language).font(.system(size: 11)).foregroundStyle(theme.mutedColor)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.mutedColor)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(theme.textColor)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                    .fixedSize(horizontal: true, vertical: true)
            }
        }
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.surfaceColor))
    }
}

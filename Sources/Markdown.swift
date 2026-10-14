import SwiftUI

/// Claude の報告を描く。報告は Markdown で書かれていて、そのまま出すと `#` や `**` が記号のまま並んだ（2026-10-14）。
/// 見出し・箇条書き・番号付きの行・コードの塊・区切り線を行ごとに見分け、行の中の太字やコードは
/// AttributedString に任せる。表や引用は見分けず、ふつうの行として出す
enum Markdown {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        /// 箇条書きと番号付きの行。marker は「•」か「1.」
        case item(marker: String, depth: Int, text: String)
        case code(String)
        case paragraph(String)
        case rule
    }

    static func blocks(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))) }
            paragraph = []
        }
        for raw in source.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil {
                code?.append(raw)
                continue
            }
            if line.isEmpty {
                flush()
                continue
            }
            let hashes = line.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), line.dropFirst(hashes).first == " " {
                flush()
                blocks.append(.heading(level: hashes, text: String(line.dropFirst(hashes + 1))))
                continue
            }
            if ["---", "***", "___"].contains(line) {
                flush()
                blocks.append(.rule)
                continue
            }
            // 字下げ2つで1段深い
            let depth = (raw.prefix { $0 == " " }.count) / 2
            if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
                flush()
                blocks.append(.item(marker: "•", depth: depth, text: String(line.dropFirst(2))))
                continue
            }
            let digits = line.prefix { $0.isNumber }
            if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
                flush()
                blocks.append(.item(marker: "\(digits).", depth: depth, text: String(line.dropFirst(digits.count + 2))))
                continue
            }
            paragraph.append(line)
        }
        if let code { blocks.append(.code(code.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// 行の中の太字・斜体・コード・リンク。読めなければ元の文字のまま
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

struct MarkdownView: View {
    let blocks: [Markdown.Block]

    init(_ source: String) { blocks = Markdown.blocks(source) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(block)
                    // 見出しの上は空けて、節の切れ目を見せる
                    .padding(.top, index > 0 && isHeading(block) ? 8 : 0)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isHeading(_ block: Markdown.Block) -> Bool {
        if case .heading = block { return true }
        return false
    }

    @ViewBuilder private func view(_ block: Markdown.Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(Markdown.inline(text))
                .font(level == 1 ? .title3 : .headline)
                .fontWeight(.semibold)
        case .item(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker).foregroundStyle(.secondary)
                Text(Markdown.inline(text))
            }
            .padding(.leading, CGFloat(depth) * 16)
        case .code(let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        case .paragraph(let text):
            Text(Markdown.inline(text))
        case .rule:
            Divider()
        }
    }
}

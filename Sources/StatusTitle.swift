import AppKit

/// 前回が失敗のジョブか実行中のジョブがあるときのメニューバーの絵。Hawky の StatusTitle を写した。
/// フクロウの影絵の右に、失敗は「!」の印と数、実行中は回る輪と数を描く。両方あれば上下に積み、失敗を上に置く。
/// どの場面でも印を付け、数字が自分の意味を名乗るようにする。
///
/// NSStatusItem の title は1行しか出せないので、影絵ごと1枚の絵として描く。
/// テンプレート画像にしておけば、メニューバーの明暗に合わせて OS が色を付ける。
/// テンプレートでは色は無視され、透明度だけが効く。作業中を薄くするのはその透明度で行う
@MainActor
enum StatusTitle {
    /// メニューバーの厚み。これが上限
    private static let height: CGFloat = 22
    private static let iconSize: CGFloat = 18

    /// 2段のときの書体。上下で同じにする。大きさか太さが違うと、同じ桁数でも幅が揃わず上下がずれて見える
    private static let stackedFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    /// 1段のときの書体。title で数字を出していた頃と同じ大きさにする
    private static let singleFont = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.systemFontSize(for: .regular), weight: .regular)

    /// 実行中の濃さ。手を出す必要は無いので、失敗より薄くする
    private static let runningAlpha: CGFloat = 0.55
    /// 輪の溝の濃さ。回る弧が無いところも、輪の形が分かる程度に残す
    nonisolated private static let trackAlpha: CGFloat = 0.18
    /// 印と数字の間
    private static let gap: CGFloat = 3

    /// - Parameter phase: 輪の回る位置。0 から 1 で一周する
    static func image(icon: NSImage?, failed: Int, running: Int, phase: CGFloat) -> NSImage {
        let stacked = failed > 0 && running > 0
        let font = stacked ? stackedFont : singleFont
        let line: CGFloat = stacked ? 1.6 : 2
        let rows = [
            failed > 0 ? Row(mark: .alert, count: failed, alpha: 1, font: font, line: line) : nil,
            running > 0
                ? Row(mark: .spinner(phase: phase), count: running, alpha: runningAlpha, font: font, line: line)
                : nil,
        ].compactMap { $0 }

        // 字の並ぶ線。数字の高さ（capHeight）を、1段なら枠の真ん中に、2段なら上下の余白を揃えて置く。
        // draw(at:) で描くと、行の箱の中で字がどこに来るかが書体の寸法から決まらず、印と高さがずれた
        let cap = font.capHeight
        let baselines: [CGFloat] =
            stacked
            ? [height - (height - cap * 2 - 2) / 2 - cap, (height - cap * 2 - 2) / 2]
            : [(height - cap) / 2]

        // 印は同じ幅の枠の真ん中に置き、数字はその右の列に右寄せで並べる。上下の段で印の位置も
        // 一の位の位置も揃う。桁の少ない方は印から離れるが、表の数字と同じ並べ方の方が読み比べやすい
        let markX = iconSize + 4
        // 2段のときは輪を数字と同じ高さに収める。はみ出すと、上の段の印とくっついて見える
        let markWidth = cap + (stacked ? 1 : 3)
        let textX = markX + markWidth + gap
        let width = ceil(textX + (rows.map(\.textWidth).max() ?? 0))

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            icon?.draw(in: NSRect(x: 0, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
            guard let context = NSGraphicsContext.current?.cgContext else { return true }
            for (row, baseline) in zip(rows, baselines) {
                row.draw(
                    in: context, mark: NSRect(x: markX, y: baseline, width: markWidth, height: cap),
                    textX: width - row.textWidth)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 1段分。印と数字
    private struct Row {
        enum Mark {
            case alert
            case spinner(phase: CGFloat)
        }

        let mark: Mark
        let alpha: CGFloat
        let line: CGFloat
        private let text: CTLine

        init(mark: Mark, count: Int, alpha: CGFloat, font: NSFont, line: CGFloat) {
            self.mark = mark
            self.alpha = alpha
            self.line = line
            // 色は描くときの塗りから取る。Core Text は NSColor の色の指定を読まない
            text = CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: "\(count)",
                    attributes: [
                        .font: font,
                        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
                    ]))
        }

        var textWidth: CGFloat { CGFloat(CTLineGetTypographicBounds(text, nil, nil, nil)) }

        /// - Parameter mark: 印を置く枠。下端が字の並ぶ線で、高さが数字の高さ
        func draw(in context: CGContext, mark frame: NSRect, textX: CGFloat) {
            let color = NSColor.black.withAlphaComponent(alpha)
            context.saveGState()
            context.setFillColor(color.cgColor)
            context.textMatrix = .identity
            context.textPosition = CGPoint(x: textX, y: frame.minY)
            CTLineDraw(text, context)
            context.restoreGState()

            switch mark {
            case .alert:
                // 数字と同じ高さの「!」。上に縦棒、下に点
                let bar = line * 1.25
                color.setFill()
                let stem = NSRect(
                    x: frame.midX - bar / 2, y: frame.minY + bar * 1.7, width: bar, height: frame.height - bar * 1.7)
                NSBezierPath(roundedRect: stem, xRadius: bar / 2, yRadius: bar / 2).fill()
                NSBezierPath(ovalIn: NSRect(x: frame.midX - bar / 2, y: frame.minY, width: bar, height: bar)).fill()
            case .spinner(let phase):
                // 数字の高さの真ん中を中心にした輪。溝の上を弧が時計回りに回る
                let center = NSPoint(x: frame.midX, y: frame.midY)
                let radius = frame.width / 2 - line / 2 - 0.5
                let ring = NSBezierPath()
                ring.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
                ring.lineWidth = line
                NSColor.black.withAlphaComponent(trackAlpha).setStroke()
                ring.stroke()

                let start = 90 - 360 * phase
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center, radius: radius, startAngle: start, endAngle: start - 100, clockwise: true)
                arc.lineWidth = line
                arc.lineCapStyle = .round
                color.setStroke()
                arc.stroke()
            }
        }
    }
}

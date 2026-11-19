import SwiftUI
import VomattCore

extension View {
    /// The web's `TidePanel`: Tide is the promise, a surface for what vomatt guarantees (the Seal, the rules).
    /// Never for links, buttons or headers.
    func tidePanel() -> some View {
        foregroundStyle(Tokens.tideForeground)
            .background(Tokens.tideTint, in: RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.tideLine))
    }
}

/// What an Ended Poll decided, "**Yes** won" or "Tie between **A** and **B**" (the web's `DecidedText`):
/// each winner in ink with the Elected stamp before it, wherever a result is named in a line of text.
struct DecidedText {
    let winners: [String]
    let tie: Bool

    init(winners: [String], tie: Bool) {
        self.winners = winners
        self.tie = tie
    }

    /// nil when there is no winner to name.
    init?(_ summary: EndedSummary) {
        switch summary {
        case let .won(winner): self.init(winners: [winner], tie: false)
        case let .tie(winners): self.init(winners: winners, tie: true)
        case .none: return nil
        }
    }

    /// `size` is the line's font size before Dynamic Type: the stamp is as tall as its text.
    func text(_ t: Localizer, size: CGFloat, relativeTo style: UIFont.TextStyle = .footnote) -> Text? {
        guard let first = winners.first else { return nil }
        let side = UIFontMetrics(forTextStyle: style).scaledValue(for: size)
        guard tie else { return Text.rich(t("profile.wonBy"), ["option": winner(first, side)]) }
        // The locale's list ("A, B and C"), formatted around placeholders so each name keeps its stamp
        let list = t.list(winners.indices.map { "{\($0)}" })
        let names = Dictionary(uniqueKeysWithValues: winners.enumerated().map { ("\($0.offset)", winner($0.element, side)) })
        return Text.rich(t("profile.tieBetween"), ["options": Text.rich(list, names)])
    }

    /// The name with the stamp held to its first character by a no-break space, so a wrap never strands
    /// it. The sentence around it ("won", "Tie between") carries the meaning, so VoiceOver reads the name alone.
    private func winner(_ name: String, _ side: CGFloat) -> Text {
        let color = Tokens.elected
        let stamp = Image(size: CGSize(width: side, height: side)) { context in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            context.stroke(ElectedStampShape().path(in: rect), with: .color(color), lineWidth: side * 9.5 / 130)
        }
        let ink = Text(verbatim: "\u{202F}" + name.trimmingCharacters(in: .whitespacesAndNewlines))
            .fontWeight(.medium).foregroundColor(Tokens.foreground)
        return Text(stamp).baselineOffset(-side * 0.125).accessibilityLabel(Text(verbatim: "")) + ink
    }
}

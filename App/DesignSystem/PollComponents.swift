import SwiftUI

extension View {
    /// The web's `TidePanel`: Tide is the promise, a surface for what vomatt guarantees (the Seal, the rules).
    /// Never for links, buttons or headers.
    func tidePanel() -> some View {
        foregroundStyle(Tokens.tideForeground)
            .background(Tokens.tideTint, in: RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.tideLine))
    }
}

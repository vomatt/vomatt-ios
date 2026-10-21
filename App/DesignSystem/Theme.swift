import SwiftUI

// vomatt-web DESIGN.md in SwiftUI. Colors come from `Tokens` (generated from the web's
// global.css by scripts/sync.sh tokens); sizes and shapes mirror the Tailwind classes.

enum Radius {
    /// `rounded-md`
    static let md: CGFloat = 6
    /// `rounded-lg`: buttons and inputs
    static let lg: CGFloat = 8
    /// `rounded-xl`: cards, ballot rows, panels
    static let xl: CGFloat = 12
}

enum Metrics {
    /// The page gutter (`px-contain`)
    static let gutter: CGFloat = 16
    /// `max-w-2xl`, the width of list pages
    static let listWidth: CGFloat = 672
    /// Touch targets are at least 44pt (`h-11`)
    static let minTarget: CGFloat = 44
}

extension Font {
    enum GeistWeight { case regular, medium, semibold }

    /// Geist at `size`, scaling with Dynamic Type relative to `style`. CJK falls back to PingFang TC.
    static func vm(_ size: CGFloat, _ weight: GeistWeight = .regular, relativeTo style: TextStyle = .body) -> Font {
        let name = switch weight {
        case .regular: "Geist-Regular"
        case .medium: "Geist-Medium"
        case .semibold: "Geist-SemiBold"
        }
        return .custom(name, size: size, relativeTo: style)
    }

    /// Geist Mono, for counts, times and handles.
    static func vmMono(_ size: CGFloat, medium: Bool = false, relativeTo style: TextStyle = .body) -> Font {
        .custom(medium ? "GeistMono-Medium" : "GeistMono-Regular", size: size, relativeTo: style)
    }

    /// `text-[15px]`
    static let vmBody = vm(15)
    /// `text-[13px]`
    static let vmMeta = vm(13, relativeTo: .footnote)
}

extension AnyTransition {
    /// Inline messages and toasts: fade in rising 12pt over 0.3s, fade out rising 12pt over 0.15s.
    /// Only the fade under Reduce Motion.
    static func vmEnterExit(reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)).animation(.easeOut(duration: 0.3)),
            removal: .opacity.combined(with: .offset(y: -12)).animation(.easeOut(duration: 0.15))
        )
    }
}

extension View {
    /// The `display-heading` utility: weight 400, leading 1.25, -0.03em tracking.
    func displayHeading(_ size: CGFloat) -> some View {
        font(.vm(size, relativeTo: .largeTitle))
            .tracking(-0.03 * size)
            .lineSpacing(size * 0.25)
            .foregroundStyle(Tokens.foreground)
    }

    /// The poll title: `text-[22px] leading-tight tracking-[-0.02em]`.
    func pollTitle(_ size: CGFloat = 22) -> some View {
        font(.vm(size, relativeTo: .title2))
            .tracking(-0.02 * size)
            .foregroundStyle(Tokens.foreground)
    }

    /// `bg-card border border-border rounded-xl`
    func card(padding: CGFloat? = 16, border: Color = Tokens.border) -> some View {
        self.padding(padding ?? 0)
            .background(Tokens.card, in: RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(border, lineWidth: 1))
    }

    /// `px-contain mx-auto max-w-2xl`: a centered column that fills phones.
    func pageColumn(_ maxWidth: CGFloat = Metrics.listWidth) -> some View {
        frame(maxWidth: maxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Metrics.gutter)
    }

    /// The canvas behind every screen.
    func canvas() -> some View {
        background(Tokens.background.ignoresSafeArea())
    }
}

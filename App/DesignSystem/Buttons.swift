import SwiftUI

/// The web's `Button` (`components/ui/Button.tsx`): variants and sizes with the same names.
struct VMButtonStyle: ButtonStyle {
    enum Variant { case `default`, outline, secondary, ghost, destructive, link }
    enum Size { case `default`, sm, lg, icon }

    var variant: Variant = .default
    var size: Size = .default
    var fullWidth = false
    /// `rounded-full`, for pills.
    var pill = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: pill ? 999 : Radius.lg)
        configuration.label
            .font(font)
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .frame(minWidth: size == .icon ? height : nil, maxWidth: fullWidth ? .infinity : nil)
            .frame(height: variant == .link ? nil : height)
            .frame(minHeight: Metrics.minTarget)
            .foregroundStyle(foreground)
            .background(background(pressed: configuration.isPressed), in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: variant == .outline ? 1 : 0))
            .contentShape(shape)
            .opacity(isEnabled || variant == .default ? 1 : 0.5)
            // `active:translate-y-px`
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var height: CGFloat {
        switch size {
        case .default, .sm, .icon: 44
        case .lg: 48
        }
    }

    private var horizontalPadding: CGFloat {
        switch (variant, size) {
        case (.link, _): 0
        case (_, .icon): 0
        case (_, .sm): 12
        case (_, .lg): 20
        default: 16
        }
    }

    private var font: Font {
        switch size {
        case .sm: .vm(14, .medium)
        case .lg: .vm(16, .medium)
        default: .vm(15, .medium)
        }
    }

    private var foreground: Color {
        switch variant {
        case .default: isEnabled ? Tokens.primaryForeground : Tokens.mutedForeground
        case .destructive: Tokens.destructive
        case .link: Tokens.primary
        default: Tokens.foreground
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .default: isEnabled ? (pressed ? Tokens.primaryHover : Tokens.primary) : Tokens.secondary
        case .outline: pressed ? Tokens.surfaceSoft : Tokens.card
        case .secondary: pressed ? Tokens.secondary.opacity(0.8) : Tokens.secondary
        case .ghost: pressed ? Tokens.muted : .clear
        case .destructive: Tokens.destructive.opacity(pressed ? 0.2 : 0.1)
        case .link: .clear
        }
    }

    private var border: Color {
        variant == .outline ? Tokens.border : .clear
    }
}

extension ButtonStyle where Self == VMButtonStyle {
    static var vm: VMButtonStyle { VMButtonStyle() }

    static func vm(_ variant: VMButtonStyle.Variant, size: VMButtonStyle.Size = .default, fullWidth: Bool = false, pill: Bool = false) -> VMButtonStyle {
        VMButtonStyle(variant: variant, size: size, fullWidth: fullWidth, pill: pill)
    }
}

/// A toggle pill or preset: `default` when on, `outline` when off.
struct PillButton: View {
    let title: String
    let isOn: Bool
    var pill = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(.vm(isOn ? .default : .outline, size: .sm, pill: pill))
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A button that shows a spinner while its async action runs (`ButtonLoading`).
struct LoadingButton<Label: View>: View {
    var style: VMButtonStyle = .vm
    let action: () async -> Void
    @ViewBuilder let label: () -> Label
    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading else { return }
            isLoading = true
            Task {
                await action()
                isLoading = false
            }
        } label: {
            HStack(spacing: 8) {
                if isLoading { ProgressView().tint(Tokens.primaryForeground).controlSize(.small) }
                label()
            }
        }
        .buttonStyle(style)
        .disabled(isLoading)
    }
}

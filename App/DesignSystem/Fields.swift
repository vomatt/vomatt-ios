import SwiftUI

/// The web's `Input`/`Textarea`: a `field` fill with a `border-strong` edge that turns
/// `card` white with a strong outline on focus; `destructive` edge when invalid.
struct FieldChrome: ViewModifier {
    var isFocused: Bool
    var isInvalid = false
    var minHeight: CGFloat = 48

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg)
        content
            .font(.vm(16))
            .foregroundStyle(Tokens.foreground)
            .tint(Tokens.foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: minHeight)
            .background(isFocused ? Tokens.card : Tokens.field, in: shape)
            .overlay(shape.strokeBorder(isInvalid ? Tokens.destructive : Tokens.borderStrong, lineWidth: 1))
            .overlay(shape.inset(by: -2).strokeBorder(Tokens.ring, lineWidth: isFocused ? 2 : 0))
            .animation(.easeOut(duration: 0.12), value: isFocused)
    }
}

extension View {
    func fieldChrome(isFocused: Bool, isInvalid: Bool = false, minHeight: CGFloat = 48) -> some View {
        modifier(FieldChrome(isFocused: isFocused, isInvalid: isInvalid, minHeight: minHeight))
    }
}

/// A labelled single-line field with an optional hint and error, like the web's `Field`.
struct VMTextField: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    var hint: String?
    var error: String?
    var contentType: UITextContentType?
    var keyboard: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
            }
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Tokens.mutedForeground))
                .textContentType(contentType)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled(contentType == .emailAddress || keyboard == .emailAddress)
                .submitLabel(submitLabel)
                .onSubmit(onSubmit)
                .focused($isFocused)
                .fieldChrome(isFocused: isFocused, isInvalid: error != nil)
                .accessibilityLabel(label ?? placeholder)
            if let hint {
                Text(hint).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
            if let error {
                Text(error).font(.vmMeta).foregroundStyle(Tokens.destructive)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: error)
    }
}

/// A multi-line field with the same chrome.
struct VMTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat = 80
    var font: Font = .vm(16)
    var isInvalid = false
    var autoFocus = false
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Tokens.mutedForeground), axis: .vertical)
            .font(font)
            .lineLimit(3...12)
            .focused($isFocused)
            .padding(.vertical, 12)
            .frame(minHeight: minHeight, alignment: .topLeading)
            .fieldChrome(isFocused: isFocused, isInvalid: isInvalid, minHeight: minHeight)
            .accessibilityLabel(placeholder)
            .onAppear { if autoFocus { isFocused = true } }
    }
}

/// The search field on Explore and in pickers: a field with a leading magnifier.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Tokens.mutedForeground).font(.system(size: 15))
            TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Tokens.mutedForeground))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Tokens.mutedForeground)
                }
                .accessibilityLabel("Clear")
            }
        }
        .fieldChrome(isFocused: isFocused)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(placeholder)
    }
}

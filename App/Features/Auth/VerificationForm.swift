import SwiftUI
import VomattCore

/// An `authError.*` message under the field it is about, read out when it appears (the web's `AuthError`).
struct AuthErrorText: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let error: AuthErrorKey?
    var body: some View {
        if let error {
            Label(app.t(error.translationKey), systemImage: "exclamationmark.circle")
                .font(.vmMeta)
                .foregroundStyle(Tokens.destructive)
                .transition(.vmEnterExit(reduceMotion: reduceMotion))
                .accessibilityAddTraits(.isStaticText)
                .task(id: error) { AccessibilityNotification.Announcement(app.t(error.translationKey)).post() }
        }
    }
}

private let codeLength = 6

/// The six-digit code a message carried, with Continue, a way back and a resend (the web's
/// `VerificationForm`). Sign-in and adding a phone number differ only in what checks the code.
struct VerificationForm: View {
    @Environment(AppModel.self) private var app
    let resendCooldown: Int
    let editLabel: String
    let onEdit: () -> Void
    let errorKey: (Error) -> AuthErrorKey
    /// Checks the code; what it returns runs once the number pad is gone, to move on.
    let verify: (String) async throws -> () -> Void
    let resend: () async throws -> Void

    /// `cooldown`: seconds until another code can be requested.
    init(
        cooldown: Int, resendCooldown: Int, editLabel: String, onEdit: @escaping () -> Void,
        errorKey: @escaping (Error) -> AuthErrorKey,
        verify: @escaping (String) async throws -> () -> Void, resend: @escaping () async throws -> Void
    ) {
        self.resendCooldown = resendCooldown
        self.editLabel = editLabel
        self.onEdit = onEdit
        self.errorKey = errorKey
        self.verify = verify
        self.resend = resend
        _cooldown = State(initialValue: cooldown)
    }

    @State private var code = ""
    @State private var error: AuthErrorKey?
    @State private var isVerifying = false
    @State private var cooldown: Int
    @State private var resent = false
    /// The server discarded the code (expired or too many tries): only a new one can succeed.
    /// Kept apart from `error`, so a failed resend doesn't unlock the field.
    @State private var isCodeDead = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            codeField.padding(.bottom, 8)
            AuthErrorText(error: error).padding(.bottom, 16)

            LoadingButton(style: .vm(.default, fullWidth: true), isLoading: isVerifying, action: { await submit() }) {
                Text(app.t("common.continue"))
            }
            .disabled(code.count != codeLength)
            .padding(.bottom, 12)
            Button(editLabel, action: onEdit)
                .buttonStyle(.vm(.outline, fullWidth: true))
                .padding(.bottom, 32)

            // A dead code has no server-side cooldown left, so a new one can be requested right away
            if cooldown > 0 && !isCodeDead {
                Text(app.t("verificationCode.resendIn", ["time": countdown]))
                    .font(.vm(14)).monospacedDigit().foregroundStyle(Tokens.mutedForeground)
            } else {
                LoadingButton(style: .vm(.link), action: sendAgain) {
                    Text(app.t("verificationCode.resendVerificationCode")).underline()
                }
            }
            if resent {
                Text(app.t("verificationCode.codeSent")).font(.vm(14)).foregroundStyle(Tokens.positive).padding(.top, 8)
            }
        }
        .animation(.easeOut(duration: 0.2), value: error)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .task(id: cooldown) {
            guard cooldown > 0 else { return }
            // Cancelled when the cooldown was reset: the new tick counts from the new value
            guard (try? await Task.sleep(for: .seconds(1))) != nil else { return }
            cooldown -= 1
        }
        .onAppear { isFocused = true }
    }

    /// One hidden text field drives six slots, so paste and the one-time-code autofill work.
    private var codeField: some View {
        ZStack {
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .opacity(0.02)
                .accessibilityLabel(app.t("verificationCode.inputLabel"))
                .onChange(of: code) { _, value in
                    let digits = String(value.filter(\.isNumber).prefix(codeLength))
                    if digits != value { code = digits }
                    // Clearing the field after a failed attempt must not hide the error; typing again does
                    if error != nil, !digits.isEmpty { error = nil }
                    if digits.count == codeLength { Task { await submit() } }
                }
            HStack(spacing: 8) {
                slots(0..<3)
                Text("–").foregroundStyle(Tokens.mutedForeground).accessibilityHidden(true)
                slots(3..<6)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        // Not disabled while verifying, so focus (and the keyboard) survives a wrong code.
        // A dead code needs a new one: resend or another address.
        .disabled(isCodeDead)
    }

    private func slots(_ range: Range<Int>) -> some View {
        HStack(spacing: 6) {
            ForEach(range, id: \.self) { index in
                let digits = Array(code)
                let isCurrent = isFocused && index == min(digits.count, codeLength - 1)
                let shape = RoundedRectangle(cornerRadius: Radius.lg)
                // `FieldChrome`'s focus: the edge stays and a ring goes outside it
                Text(index < digits.count ? String(digits[index]) : "")
                    .font(.vmMono(22))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(isCurrent ? Tokens.card : Tokens.field, in: shape)
                    .overlay(shape.strokeBorder(error != nil ? Tokens.destructive : Tokens.borderStrong, lineWidth: 1))
                    .overlay(shape.inset(by: -2).strokeBorder(Tokens.ring, lineWidth: isCurrent ? 2 : 0))
            }
        }
    }

    private var countdown: String {
        String(format: "%d:%02d", cooldown / 60, cooldown % 60)
    }

    private func submit() async {
        guard code.count == codeLength, !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }
        error = nil
        let submitted = code
        do {
            let proceed = try await verify(submitted)
            // The field keeps focus while verifying; drop the number pad before the next step appears
            isFocused = false
            proceed()
        } catch {
            let key = errorKey(error)
            self.error = key
            isCodeDead = key == .codeExpired || key == .tooManyAttempts
            if code == submitted || isCodeDead {
                code = ""
            } else if code.count == codeLength {
                // A code typed or pasted while this one was checked: send it once this check is over
                Task { await submit() }
            }
        }
    }

    private func sendAgain() async {
        error = nil
        resent = false
        do {
            try await resend()
            resent = true
            isCodeDead = false
            code = ""
            cooldown = resendCooldown
        } catch {
            if let seconds = (error as? APIError)?.cooldownSeconds {
                cooldown = seconds
            } else {
                self.error = errorKey(error)
            }
        }
    }
}

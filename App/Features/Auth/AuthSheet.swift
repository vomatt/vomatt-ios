import SwiftUI
import VomattCore

/// One flow for sign-in and sign-up (the web's `AuthFlow`): email → code → (new accounts) display name.
struct AuthSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onSignedIn: (() -> Void)?

    enum Step { case email, code, profile }
    @State private var step = Step.email
    @State private var email = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .email:
                        EmailStep(email: $email) { withAnimation { step = .code } }
                    case .code:
                        CodeStep(email: email, onEditEmail: { withAnimation { step = .email } }) { isNewUser in
                            if isNewUser { withAnimation { step = .profile } } else { finish() }
                        }
                    case .profile:
                        ProfileStep(email: email, onDone: finish)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .canvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(app.t("common.close")) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Image("brand-logo").renderingMode(.template).resizable().scaledToFit()
                        .frame(height: 18).foregroundStyle(Tokens.foreground)
                        .accessibilityLabel("vomatt")
                }
            }
        }
        .interactiveDismissDisabled(step == .profile)
    }

    private func finish() {
        dismiss()
        onSignedIn?()
    }
}

private struct AuthErrorText: View {
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

private struct EmailStep: View {
    @Environment(AppModel.self) private var app
    @Binding var email: String
    let onSent: () -> Void
    @State private var fieldError: String?
    @State private var error: AuthErrorKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.t("login.title")).displayHeading(32).padding(.bottom, 12)
            Text(app.t("login.subtitle")).font(.vm(16)).foregroundStyle(Tokens.mutedForeground)
                .lineSpacing(4).padding(.bottom, 32)
            VMTextField(
                label: app.t("common.email"), placeholder: "you@example.com", text: $email, error: fieldError,
                contentType: .emailAddress, keyboard: .emailAddress, autocapitalization: .never, submitLabel: .continue
            )
            .padding(.bottom, 20)
            LoadingButton(style: .vm(.default, fullWidth: true), action: submit) {
                Text(app.t("auth.continueWithEmail"))
            }
            AuthErrorText(error: error).padding(.top, 12)
        }
        .animation(.easeOut(duration: 0.2), value: error)
    }

    private func submit() async {
        error = nil
        guard Email.isValid(email) else {
            fieldError = app.t("common.invalidEmailAddress")
            return
        }
        fieldError = nil
        do {
            try await app.service.requestOtp(email: email)
            email = email.trimmingCharacters(in: .whitespacesAndNewlines)
            onSent()
        } catch {
            self.error = AuthErrorKey(error)
        }
    }
}

/// Matches the backend's default OTP resend cooldown.
private let resendCooldown = 180
private let codeLength = 6

private struct CodeStep: View {
    @Environment(AppModel.self) private var app
    let email: String
    let onEditEmail: () -> Void
    let onVerified: (_ isNewUser: Bool) -> Void

    @State private var code = ""
    @State private var error: AuthErrorKey?
    @State private var isVerifying = false
    @State private var cooldown = resendCooldown
    @State private var resent = false
    /// The server discarded the code (expired or too many tries): only a new one can succeed.
    /// Kept apart from `error`, so a failed resend doesn't unlock the field.
    @State private var isCodeDead = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 22))
                .foregroundStyle(Tokens.foreground)
                .frame(width: 48, height: 48)
                .background(Tokens.highlight, in: Circle())
                .overlay(Circle().strokeBorder(Tokens.foreground.opacity(0.2)))
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            Text(app.t("verificationCode.title")).displayHeading(32).padding(.bottom, 12)
            (Text(app.t("verificationCode.subtitle") + " ").foregroundStyle(Tokens.mutedForeground)
                + Text(email).font(.vm(16, .medium)).foregroundStyle(Tokens.foreground))
                .font(.vm(16)).lineSpacing(4).padding(.bottom, 32)

            codeField.padding(.bottom, 8)
            AuthErrorText(error: error).padding(.bottom, 16)

            LoadingButton(style: .vm(.default, fullWidth: true), isLoading: isVerifying, action: { await verify() }) {
                Text(app.t("common.continue"))
            }
            .disabled(code.count != codeLength)
            .padding(.bottom, 12)
            Button(app.t("verificationCode.useAnotherEmail"), action: onEditEmail)
                .buttonStyle(.vm(.outline, fullWidth: true))
                .padding(.bottom, 32)

            // A dead code has no server-side cooldown left, so a new one can be requested right away
            if cooldown > 0 && !isCodeDead {
                Text(app.t("verificationCode.resendIn", ["time": countdown]))
                    .font(.vm(14)).monospacedDigit().foregroundStyle(Tokens.mutedForeground)
            } else {
                LoadingButton(style: .vm(.link), action: resend) {
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
            try? await Task.sleep(for: .seconds(1))
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
                    if digits.count == codeLength { Task { await verify() } }
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
        // A dead code needs a new one: resend or another email.
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

    private func verify() async {
        guard code.count == codeLength, !isVerifying else { return }
        isVerifying = true
        defer { isVerifying = false }
        error = nil
        let submitted = code
        do {
            let isNewUser = try await app.service.verifyOtp(email: email, code: submitted)
            // The field keeps focus while verifying; drop the number pad before the next step appears
            isFocused = false
            onVerified(isNewUser)
        } catch {
            let key = AuthErrorKey(error)
            self.error = key
            isCodeDead = key == .codeExpired || key == .tooManyAttempts
            if code == submitted || isCodeDead {
                code = ""
            } else if code.count == codeLength {
                // A code typed or pasted while this one was checked: send it once this check is over
                Task { await verify() }
            }
        }
    }

    private func resend() async {
        error = nil
        resent = false
        do {
            try await app.service.requestOtp(email: email)
            resent = true
            isCodeDead = false
            code = ""
            cooldown = resendCooldown
        } catch {
            self.error = AuthErrorKey(error)
        }
    }
}

private struct ProfileStep: View {
    @Environment(AppModel.self) private var app
    let email: String
    let onDone: () -> Void
    @State private var displayName = ""
    @State private var fieldError: String?
    @State private var error: AuthErrorKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.t("onboarding.title")).displayHeading(32).padding(.bottom, 12)
            Text(app.t("onboarding.subtitle")).font(.vm(16)).foregroundStyle(Tokens.mutedForeground).padding(.bottom, 32)
            VMTextField(
                label: app.t("onboarding.displayName"), placeholder: "", text: $displayName,
                hint: app.t("onboarding.displayNameHint"), error: fieldError, contentType: .nickname
            )
            .padding(.bottom, 20)
            LoadingButton(style: .vm(.default, fullWidth: true), action: save) { Text(app.t("onboarding.finish")) }
                .padding(.bottom, 12)
            Button(app.t("onboarding.skip"), action: onDone).buttonStyle(.vm(.ghost, fullWidth: true))
            AuthErrorText(error: error).padding(.top, 12)
        }
        .onAppear { if displayName.isEmpty { displayName = String(email.split(separator: "@").first ?? "") } }
    }

    private func save() async {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count <= 100 else {
            fieldError = app.t("onboarding.displayNameTooLong")
            return
        }
        fieldError = nil
        do {
            try await app.service.updateProfile(displayName: name)
            app.updateMe { $0.displayName = name }
            onDone()
        } catch {
            // The account already exists, so this isn't fatal
            self.error = .serverError
        }
    }
}

import SwiftUI
import VomattCore

/// One flow for sign-in and sign-up (the web's `AuthFlow`): email → code → first and last name (new
/// accounts, and ones that never gave a first name).
struct AuthSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var onSignedIn: (() -> Void)?

    enum Step: Equatable { case email, code, profile(NameStep) }
    @State private var step = Step.email
    @State private var email = ""
    @State private var cooldown = resendCooldown

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .email:
                        EmailStep(email: $email, onSent: { seconds in
                            cooldown = seconds
                            withAnimation { step = .code }
                        }, onPasskeySignedIn: finish)
                    case .code:
                        CodeStep(email: email, cooldown: cooldown, onEditEmail: { withAnimation { step = .email } }) { nameStep in
                            if let nameStep { withAnimation { step = .profile(nameStep) } } else { finish() }
                        }
                    case let .profile(nameStep):
                        ProfileStep(username: nameStep.username, onDone: finish)
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
                    // Past the code the account is signed in, so closing at the name step still continues the action
                    Button(app.t("common.close")) { if isAtProfile { finish() } else { dismiss() } }
                }
                ToolbarItem(placement: .principal) {
                    Image("brand-logo").renderingMode(.template).resizable().scaledToFit()
                        .frame(height: 18).foregroundStyle(Tokens.foreground)
                        .accessibilityLabel("vomatt")
                }
            }
        }
        .interactiveDismissDisabled(isAtProfile)
    }

    private var isAtProfile: Bool {
        if case .profile = step { true } else { false }
    }

    private func finish() {
        dismiss()
        onSignedIn?()
    }
}

private struct EmailStep: View {
    @Environment(AppModel.self) private var app
    @Binding var email: String
    /// Called with the seconds until another code can be requested.
    let onSent: (Int) -> Void
    /// A passkey account is already set up, so there is no profile step.
    let onPasskeySignedIn: () -> Void
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
            LoadingButton(style: .vm(.outline, fullWidth: true), action: signInWithPasskey) {
                Text(app.t("auth.continueWithPasskey"))
            }
            .padding(.top, 8)
            AuthErrorText(error: error).padding(.top, 12)
            Text(policy).font(.vm(12)).foregroundStyle(Tokens.mutedForeground).tint(Tokens.mutedForeground)
                .padding(.top, 20)
        }
        .animation(.easeOut(duration: 0.2), value: error)
    }

    /// The web's Sanity `policyMessage`, with its two links.
    private var policy: AttributedString {
        let markdown = app.t("ios.signUpPolicy", ["terms": LegalLinks.terms(app.language), "privacy": LegalLinks.privacy(app.language)])
        var text = (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
        for run in text.runs where run.link != nil {
            text[run.range].underlineStyle = .single
        }
        return text
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
            onSent(resendCooldown)
        } catch {
            if let seconds = (error as? APIError)?.cooldownSeconds {
                // The code sent moments ago still works, so go on to enter it (vomatt-web#119)
                email = email.trimmingCharacters(in: .whitespacesAndNewlines)
                onSent(seconds)
            } else {
                self.error = AuthErrorKey(error)
            }
        }
    }

    private func signInWithPasskey() async {
        error = nil
        do {
            let challenge = try await app.service.passkeySignInChallenge()
            let assertion = try await PasskeyAuthenticator.signIn(challenge: challenge)
            try await app.service.signIn(with: assertion)
            onPasskeySignedIn()
        } catch {
            self.error = AuthErrorKey(passkeyError: error)
        }
    }
}

/// Matches the backend's default OTP resend cooldown.
private let resendCooldown = 180

private struct CodeStep: View {
    @Environment(AppModel.self) private var app
    let email: String
    let cooldown: Int
    let onEditEmail: () -> Void
    /// Nil when the account is signed in and nothing else is asked.
    let onVerified: (NameStep?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 22))
                .foregroundStyle(Tokens.tideForeground)
                .frame(width: 48, height: 48)
                .background(Tokens.tideTint, in: Circle())
                .overlay(Circle().strokeBorder(Tokens.tideLine))
                .padding(.bottom, 20)
                .accessibilityHidden(true)
            Text(app.t("verificationCode.title")).displayHeading(32).padding(.bottom, 12)
            (Text(app.t("verificationCode.subtitle") + " ").foregroundStyle(Tokens.mutedForeground)
                + Text(email).font(.vm(16, .medium)).foregroundStyle(Tokens.foreground))
                .font(.vm(16)).lineSpacing(4).padding(.bottom, 32)
            VerificationForm(
                cooldown: cooldown, resendCooldown: resendCooldown,
                editLabel: app.t("verificationCode.useAnotherEmail"), onEdit: onEditEmail,
                errorKey: { AuthErrorKey($0) },
                verify: { code in
                    let signIn = try await app.service.verifyOtp(email: email, code: code)
                    let me = signIn.isNewUser ? nil : try? await app.service.myProfile()
                    return { onVerified(NameStep.after(signIn, me: me)) }
                },
                resend: { try await app.service.requestOtp(email: email) }
            )
        }
    }
}

private struct ProfileStep: View {
    @Environment(AppModel.self) private var app
    let username: String?
    let onDone: () -> Void
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var firstNameError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.t("onboarding.title")).displayHeading(32).padding(.bottom, 12)
            Text(username.map { app.t("onboarding.subtitle", ["username": $0]) } ?? app.t("onboarding.subtitleNoUsername"))
                .font(.vm(16)).foregroundStyle(Tokens.mutedForeground).padding(.bottom, 32)
            VStack(alignment: .leading, spacing: 12) {
                VMTextField(
                    label: app.t("profile.firstName"), placeholder: "", text: limited($firstName), error: firstNameError,
                    contentType: .givenName, submitLabel: .next
                )
                VMTextField(label: app.t("profile.lastName"), placeholder: "", text: limited($lastName), contentType: .familyName)
            }
            .padding(.bottom, 20)
            LoadingButton(style: .vm(.default, fullWidth: true), action: save) { Text(app.t("onboarding.finish")) }
        }
    }

    /// The fields stop at the backend's cap, so it needs no message of its own.
    private func limited(_ text: Binding<String>) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(SignUpName.maxLength)) })
    }

    private func save() async {
        guard let name = SignUpName(firstName: firstName, lastName: lastName) else {
            firstNameError = app.t("common.required")
            return
        }
        firstNameError = nil
        do {
            try await app.service.updateProfile(firstName: name.firstName, lastName: name.lastName)
            app.updateMe {
                $0.firstName = name.firstName
                if let lastName = name.lastName { $0.lastName = lastName }
            }
        } catch {
            // The account is already signed in, so a failed save mustn't hold the person here
            app.showToast(app.t("onboarding.saveFailed"), isError: true)
        }
        onDone()
    }
}

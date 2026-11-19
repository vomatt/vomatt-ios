import SwiftUI
import VomattCore

/// Adds or verifies the signed-in account's phone number (the web's `PhoneBindDialog`): the number, then
/// the code texted to it. A wrong code is an error on the code, never a sign-out.
struct PhoneBindSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Prefills the number: a bound one that still needs verifying, or nil.
    let defaultPhone: String?

    private enum Step { case phone, code }
    @State private var step = Step.phone
    @State private var phone = ""
    @State private var cooldown = PhoneBindSheet.resendCooldown

    /// Matches the backend's default OTP resend cooldown.
    static let resendCooldown = 180

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch step {
                    case .phone:
                        PhoneStep(phone: $phone) { seconds in
                            cooldown = seconds
                            withAnimation { step = .code }
                        }
                    case .code:
                        codeStep
                    }
                }
                .padding(24)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .canvas()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(app.t("common.close")) { dismiss() } }
            }
        }
        .onAppear { phone = defaultPhone ?? "" }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.t("phoneBind.codeTitle")).displayHeading(32).padding(.bottom, 12)
            (Text(app.t("phoneBind.codeSubtitle") + " ").foregroundStyle(Tokens.mutedForeground)
                + Text(phone).font(.vm(16, .medium)).foregroundStyle(Tokens.foreground))
                .font(.vm(16)).lineSpacing(4).padding(.bottom, 32)
            VerificationForm(
                cooldown: cooldown, resendCooldown: Self.resendCooldown,
                editLabel: app.t("phoneBind.useAnotherNumber"), onEdit: { withAnimation { step = .phone } },
                errorKey: { AuthErrorKey(phoneBindError: $0) },
                verify: { code in
                    let me = try await app.service.verifyPhoneBind(phone: phone, code: code)
                    return {
                        app.updateMe { $0 = me }
                        app.showToast(app.t("phoneBind.done"))
                        dismiss()
                    }
                },
                resend: { try await app.service.sendPhoneBindOtp(phone: phone) }
            )
        }
    }
}

private struct PhoneStep: View {
    @Environment(AppModel.self) private var app
    @Binding var phone: String
    /// Called with the seconds until another code can be requested.
    let onSent: (Int) -> Void
    /// The API's reason a number was refused, shown on the field.
    @State private var fieldError: String?
    @State private var error: AuthErrorKey?

    private var number: String { phone.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(app.t("phoneBind.title")).displayHeading(32).padding(.bottom, 12)
            Text(app.t("phoneBind.subtitle")).font(.vm(16)).foregroundStyle(Tokens.mutedForeground)
                .lineSpacing(4).padding(.bottom, 32)
            VMTextField(
                label: app.t("phoneBind.label"), placeholder: "0912345678", text: $phone,
                hint: app.t("phoneBind.hint"), error: fieldError,
                contentType: .telephoneNumber, keyboard: .phonePad, autoFocus: true
            )
            .onChange(of: phone) {
                fieldError = nil
                error = nil
            }
            .padding(.bottom, 20)
            LoadingButton(style: .vm(.default, fullWidth: true), action: submit) { Text(app.t("phoneBind.sendCode")) }
                .disabled(number.isEmpty)
            AuthErrorText(error: error).padding(.top, 12)
        }
        .animation(.easeOut(duration: 0.2), value: error)
    }

    private func submit() async {
        fieldError = nil
        error = nil
        do {
            try await app.service.sendPhoneBindOtp(phone: number)
            phone = number
            onSent(PhoneBindSheet.resendCooldown)
        } catch {
            if let seconds = (error as? APIError)?.cooldownSeconds {
                // An earlier code sent within the cooldown is still valid: both last 180 s
                phone = number
                onSent(seconds)
            } else if (error as? APIError)?.errorCode == "auth.phone.invalid" {
                fieldError = app.t.message(for: error, fallback: AuthErrorKey.serverError.translationKey)
            } else {
                self.error = AuthErrorKey(phoneBindError: error)
            }
        }
    }
}

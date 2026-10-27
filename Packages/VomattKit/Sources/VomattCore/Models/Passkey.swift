import AuthenticationServices
import Foundation

/// The relying party every passkey belongs to: vomatt.com, admin.vomatt.com and the app share it.
public let passkeyRelyingParty = "vomatt.com"

/// What the authenticator returns for a passkey sign-in
/// (`ASAuthorizationPlatformPublicKeyCredentialAssertion`).
public struct PasskeyAssertion: Sendable {
    public var credentialID: Data
    public var clientDataJSON: Data
    public var authenticatorData: Data
    public var signature: Data
    /// The account's user handle; passkeys made by vomatt always carry it.
    public var userID: Data?

    public init(credentialID: Data, clientDataJSON: Data, authenticatorData: Data, signature: Data, userID: Data?) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.authenticatorData = authenticatorData
        self.signature = signature
        self.userID = userID
    }
}

/// The person closed the system passkey sheet (or the device has no passkey for vomatt.com):
/// nothing to report, like the web's `NotAllowedError`.
public func isPasskeyCancellation(_ error: Error) -> Bool {
    (error as? ASAuthorizationError)?.code == .canceled
}

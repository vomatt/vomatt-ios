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

/// What `/register/options` asks the authenticator for: the account the new passkey belongs to.
public struct PasskeyRegistrationOptions: Equatable, Sendable {
    public var challenge: Data
    /// Shown in the system passkey sheet and the Passwords app (the account's email or username).
    public var userName: String
    /// The account's user handle; a sign-in with the passkey returns it.
    public var userID: Data
    /// The account's existing passkeys, which the authenticator refuses to make again.
    public var excludedCredentialIDs: [Data]

    public init(challenge: Data, userName: String, userID: Data, excludedCredentialIDs: [Data] = []) {
        self.challenge = challenge
        self.userName = userName
        self.userID = userID
        self.excludedCredentialIDs = excludedCredentialIDs
    }
}

/// What the authenticator returns for a new passkey
/// (`ASAuthorizationPlatformPublicKeyCredentialRegistration`).
public struct PasskeyRegistration: Sendable {
    public var credentialID: Data
    public var clientDataJSON: Data
    public var attestationObject: Data

    public init(credentialID: Data, clientDataJSON: Data, attestationObject: Data) {
        self.credentialID = credentialID
        self.clientDataJSON = clientDataJSON
        self.attestationObject = attestationObject
    }
}

/// A passkey on the signed-in account. Key material never leaves the API.
public struct Passkey: Identifiable, Equatable, Sendable {
    public let id: String
    /// nil when none was given at registration.
    public var name: String?
    public var createdAt: Date
    /// nil until it first signs in.
    public var lastUsedAt: Date?

    public init(id: String, name: String?, createdAt: Date, lastUsedAt: Date?) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

/// The person closed the system passkey sheet (or the device has no passkey for vomatt.com):
/// nothing to report, like the web's `NotAllowedError`.
public func isPasskeyCancellation(_ error: Error) -> Bool {
    (error as? ASAuthorizationError)?.code == .canceled
}

/// The device already holds one of the account's passkeys (`excludedCredentialIDs`), like the
/// web's `InvalidStateError`.
func isExcludedPasskey(_ error: Error) -> Bool {
    guard #available(iOS 18, macOS 15, *) else { return false }
    return (error as? ASAuthorizationError)?.code == .matchedExcludedCredential
}

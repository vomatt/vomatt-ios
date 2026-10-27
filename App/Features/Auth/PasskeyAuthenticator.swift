import AuthenticationServices
import UIKit
import VomattCore

/// Runs one system passkey request for vomatt.com and hands back what the authenticator signed.
/// `ASAuthorizationController` keeps its delegate weakly, so the authenticator holds itself
/// until the request ends.
final class PasskeyAuthenticator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorization, Error>?
    private var retainedUntilDone: PasskeyAuthenticator?

    /// Signs `challenge` (from `/login/options`) with a passkey already on the device.
    static func signIn(challenge: Data) async throws -> PasskeyAssertion {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: passkeyRelyingParty)
        let request = provider.createCredentialAssertionRequest(challenge: challenge)
        let authorization = try await PasskeyAuthenticator().perform(request, options: .preferImmediatelyAvailableCredentials)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            throw ASAuthorizationError(.failed)
        }
        return PasskeyAssertion(
            credentialID: credential.credentialID, clientDataJSON: credential.rawClientDataJSON,
            authenticatorData: credential.rawAuthenticatorData, signature: credential.signature, userID: credential.userID
        )
    }

    /// Makes a passkey on this device for the account in `options` (from `/register/options`).
    static func register(_ options: PasskeyRegistrationOptions) async throws -> PasskeyRegistration {
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: passkeyRelyingParty)
        let request = provider.createCredentialRegistrationRequest(
            challenge: options.challenge, name: options.userName, userID: options.userID
        )
        let authorization = try await PasskeyAuthenticator().perform(request)
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let attestationObject = credential.rawAttestationObject
        else { throw ASAuthorizationError(.failed) }
        return PasskeyRegistration(
            credentialID: credential.credentialID, clientDataJSON: credential.rawClientDataJSON, attestationObject: attestationObject
        )
    }

    private func perform(_ request: ASAuthorizationRequest, options: ASAuthorizationController.RequestOptions = []) async throws -> ASAuthorization {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            retainedUntilDone = self
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests(options: options)
        }
    }

    private func finish(_ result: Result<ASAuthorization, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        retainedUntilDone = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        finish(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        finish(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}

import AuthenticationServices
import Foundation
import Testing
@testable import VomattCore

private let base = URL(string: "https://api.test")!

/// Bytes whose standard base64 ("+/8=") has every character base64url replaces or drops.
private let awkward = Data([0xFB, 0xFF])

private func json(_ text: String?) throws -> [String: Any] {
    let text = try #require(text)
    return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

@Suite("Passkeys")
struct PasskeyTests {
    @Test func base64URLHasNoPaddingAndRoundTrips() {
        #expect(awkward.base64URLEncodedString() == "-_8")
        #expect(Data(base64URLEncoded: "-_8") == awkward)
    }

    @Test func signInChallengeIsDecodedFromBase64URL() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"challenge":"-_8","rpId":"vomatt.com","allowCredentials":[],"timeout":300000,"userVerification":"preferred"}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)

        #expect(try await service.passkeySignInChallenge() == awkward)
        #expect(transport.requests.first?.path == "/api/auth/passkey/login/options")
    }

    @Test func assertionIsSentLikeTheBrowsersToJSON() async throws {
        let store = InMemoryTokenStore(AuthTokens(accessToken: "old", refreshToken: "old-r"))
        let transport = StubTransport { _, _ in (200, envelope(#"{"token":"a","refreshToken":"r","isNewUser":false}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: store, language: { .en }, transport: transport)

        try await service.signIn(with: PasskeyAssertion(
            credentialID: awkward, clientDataJSON: Data("{}".utf8), authenticatorData: Data([0x01, 0xFE]),
            signature: Data([0x3E, 0x3F]), userID: Data([0xFF])
        ))

        let request = try #require(transport.requests.first)
        #expect(request.path == "/api/auth/passkey/login/verify")
        #expect(request.authorization == nil)
        let credential = try #require(try json(request.body)["credential"] as? [String: Any])
        #expect(Set(credential.keys) == ["id", "rawId", "type", "authenticatorAttachment", "clientExtensionResults", "response"])
        #expect(credential["id"] as? String == "-_8")
        #expect(credential["rawId"] as? String == "-_8")
        #expect(credential["type"] as? String == "public-key")
        #expect(credential["authenticatorAttachment"] as? String == "platform")
        #expect((credential["clientExtensionResults"] as? [String: Any])?.isEmpty == true)
        let response = try #require(credential["response"] as? [String: String])
        #expect(response == [
            "clientDataJSON": "e30", "authenticatorData": "Af4", "signature": "Pj8", "userHandle": "_w",
        ])
        #expect(store.load() == AuthTokens(accessToken: "a", refreshToken: "r"))
    }

    @Test func cancellingTheSheetShowsNoError() {
        #expect(AuthErrorKey(passkeyError: ASAuthorizationError(.canceled)) == nil)
        #expect(isPasskeyCancellation(ASAuthorizationError(.canceled)))
        #expect(!isPasskeyCancellation(ASAuthorizationError(.failed)))
    }

    @Test func aRejectedPasskeyShowsAnErrorAndStaysSignedOut() async throws {
        let store = InMemoryTokenStore()
        let transport = StubTransport { _, _ in (401, failure("auth.passkey.invalid"), [:]) }
        let service = VomattService(baseURL: base, tokenStore: store, language: { .en }, transport: transport)

        let error = await #expect(throws: APIError.self) {
            try await service.signIn(with: PasskeyAssertion(
                credentialID: awkward, clientDataJSON: Data(), authenticatorData: Data(), signature: Data(), userID: nil
            ))
        }
        #expect(AuthErrorKey(passkeyError: try #require(error)) == .passkeyInvalid)
        #expect(store.load() == nil)
        // A 401 here is the passkey's, not the session's: no refresh attempt
        #expect(transport.requests.count == 1)
    }
}

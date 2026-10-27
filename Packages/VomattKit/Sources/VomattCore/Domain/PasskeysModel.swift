import Foundation
import Observation

/// What to show for a failed passkey action: the API's message for `error` when it has one,
/// else the string at `key` (`Localizer.message(for:fallback:)`).
public struct PasskeyFailure: Sendable {
    public let key: String
    public let error: (any Error)?
}

/// The account page's passkeys (the web's `PasskeysPanel`).
@MainActor
@Observable
public final class PasskeysModel {
    /// The last failed action; cancelling the system sheet isn't one.
    public private(set) var failure: PasskeyFailure?

    private let service: VomattService

    public init(service: VomattService) {
        self.service = service
    }

    /// Registers a passkey on this device. `authenticate` runs the system sheet with the
    /// options from the API. True when the passkey was added.
    @discardableResult
    public func add(authenticate: (PasskeyRegistrationOptions) async throws -> PasskeyRegistration) async -> Bool {
        failure = nil
        do {
            let options = try await service.passkeyRegistrationOptions()
            let registration = try await authenticate(options)
            try await service.registerPasskey(registration)
            return true
        } catch {
            if isPasskeyCancellation(error) { return false }
            // A conflict is a passkey this account already has
            failure = (error as? APIError)?.isBusy == true
                ? PasskeyFailure(key: "passkey.alreadyAdded", error: nil)
                : PasskeyFailure(key: "passkey.addFailed", error: error)
            return false
        }
    }
}

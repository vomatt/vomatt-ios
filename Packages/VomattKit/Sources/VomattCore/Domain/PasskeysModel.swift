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
    /// nil until the first load.
    public private(set) var passkeys: [Passkey]?
    public private(set) var loadFailed = false
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
            await load()
            return true
        } catch {
            if isPasskeyCancellation(error) { return false }
            // The device or the API already has this account's passkey
            failure = isExcludedPasskey(error) || (error as? APIError)?.isBusy == true
                ? PasskeyFailure(key: "passkey.alreadyAdded", error: nil)
                : PasskeyFailure(key: "passkey.addFailed", error: error)
            return false
        }
    }

    public func load() async {
        do {
            passkeys = try await service.passkeys()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Removes the passkey once the API has; on failure it stays listed. True when removed.
    @discardableResult
    public func delete(_ passkey: Passkey) async -> Bool {
        failure = nil
        do {
            try await service.deletePasskey(id: passkey.id)
            passkeys?.removeAll { $0.id == passkey.id }
            return true
        } catch {
            failure = PasskeyFailure(key: "passkey.deleteFailed", error: error)
            return false
        }
    }
}

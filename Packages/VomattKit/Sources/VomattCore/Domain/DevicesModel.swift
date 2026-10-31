import Foundation
import Observation

/// The account page's signed-in devices (the sessions that can still refresh).
@MainActor
@Observable
public final class DevicesModel {
    /// nil until the first load.
    public private(set) var devices: [DeviceSession]?
    public private(set) var loadFailed = false
    /// The last failed sign-out.
    public private(set) var failure: (any Error)?

    private let service: VomattService

    public init(service: VomattService) {
        self.service = service
    }

    public var hasOthers: Bool { devices?.contains { !$0.isCurrent } ?? false }

    public func load() async {
        do {
            devices = try await service.deviceSessions()
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    /// Signs the device out once the API has; one that is already gone (404) just leaves the list.
    /// True when it's no longer listed.
    @discardableResult
    public func signOut(_ device: DeviceSession) async -> Bool {
        failure = nil
        do {
            try await service.signOutDevice(id: device.id)
        } catch let error as APIError where error.isNotFound {
            // Someone else signed it out first
        } catch {
            failure = error
            return false
        }
        devices?.removeAll { $0.id == device.id }
        return true
    }

    /// True when every other session is signed out.
    @discardableResult
    public func signOutOthers() async -> Bool {
        failure = nil
        do {
            try await service.signOutOtherDevices()
            devices?.removeAll { !$0.isCurrent }
            return true
        } catch {
            failure = error
            return false
        }
    }
}

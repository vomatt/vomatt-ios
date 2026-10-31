import Foundation
import Testing
@testable import VomattCore

private let base = URL(string: "https://api.test")!

private let listed = envelope("""
[{"sessionId":"s-1","userAgent":"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1","createdAt":"2026-10-01T08:00:00Z","lastSeenAt":"2026-10-29T08:00:00Z","current":true,"adminScope":false},
{"sessionId":"s-2","userAgent":null,"createdAt":null,"lastSeenAt":null,"current":false,"adminScope":true}]
""")

@Suite("Devices")
struct DeviceSessionTests {
    private func service(_ handler: @escaping StubTransport.Handler) -> (VomattService, StubTransport) {
        let transport = StubTransport(handler: handler)
        let access = TokenClaimTests.token(sub: "user-1", exp: Date.now.timeIntervalSince1970 + 3600)
        let store = InMemoryTokenStore(AuthTokens(accessToken: access, refreshToken: "refresh-1"))
        return (VomattService(baseURL: base, tokenStore: store, language: { .en }, transport: transport), transport)
    }

    @Test func namesComeFromTheUserAgent() {
        let name = { (ua: String) in DeviceName(userAgent: ua)?.text }
        #expect(name("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1") == "iPhone · Safari")
        #expect(name("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36") == "Mac · Chrome")
        #expect(name("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36 Edg/131.0") == "Windows · Edge")
        #expect(name("Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36") == "Android · Chrome")
        #expect(name("Vomatt/1 CFNetwork/1568 Darwin/24.0") == "Vomatt")
        #expect(name("curl/8.0") == nil)
    }

    @Test func listsDevicesWithUnknownOnesKept() async throws {
        let (service, transport) = service { _, _ in (200, listed, [:]) }
        let devices = try await service.deviceSessions()

        #expect(transport.requests.map(\.path) == ["/api/users/me/sessions"])
        #expect(devices.map(\.id) == ["s-1", "s-2"])
        #expect(devices[0].isCurrent && devices[0].deviceName == "iPhone · Safari")
        #expect(devices[0].lastSeenAt != nil)
        #expect(devices[1].deviceName == nil && devices[1].createdAt == nil && devices[1].isAdminScope)
    }

    @MainActor @Test func signingOutADeviceRemovesItFromTheList() async throws {
        let (service, transport) = service { request, _ in
            request.method == .get ? (200, listed, [:]) : (200, envelope("null"), [:])
        }
        let model = DevicesModel(service: service)
        await model.load()
        let other = try #require(model.devices?.last)

        #expect(await model.signOut(other))
        #expect(model.devices?.map(\.id) == ["s-1"])
        #expect(!model.hasOthers)
        #expect(transport.requests.last?.method == .delete)
        #expect(transport.requests.last?.path == "/api/users/me/sessions/s-2")
    }

    @MainActor @Test func aDeviceAlreadyGoneLeavesTheList() async throws {
        let (service, _) = service { request, _ in
            request.method == .get ? (200, listed, [:]) : (404, failure("auth.session_not_found"), [:])
        }
        let model = DevicesModel(service: service)
        await model.load()
        let other = try #require(model.devices?.last)

        #expect(await model.signOut(other))
        #expect(model.failure == nil)
        #expect(model.devices?.count == 1)
    }

    @MainActor @Test func aFailedSignOutKeepsTheDevice() async throws {
        let (service, _) = service { request, _ in
            request.method == .get ? (200, listed, [:]) : (429, failure("common.rate_limited"), [:])
        }
        let model = DevicesModel(service: service)
        await model.load()
        let other = try #require(model.devices?.last)

        #expect(await model.signOut(other) == false)
        #expect((model.failure as? APIError)?.isRateLimited == true)
        #expect(model.devices?.count == 2)
    }

    @MainActor @Test func signingOutOthersKeepsThisDevice() async throws {
        let (service, transport) = service { request, _ in
            request.method == .get ? (200, listed, [:]) : (200, envelope("null"), [:])
        }
        let model = DevicesModel(service: service)
        await model.load()
        #expect(model.hasOthers)

        #expect(await model.signOutOthers())
        #expect(model.devices?.map(\.id) == ["s-1"])
        #expect(transport.requests.last?.path == "/api/users/me/sessions?scope=others")
        #expect(transport.requests.last?.method == .delete)
    }

    @MainActor @Test func aListThatFailsToLoadCanBeRetried() async {
        let (service, _) = service { _, _ in (500, failure("common.internal_error"), [:]) }
        let model = DevicesModel(service: service)
        await model.load()
        #expect(model.loadFailed && model.devices == nil)
    }

    @Test func aRevokedSessionSignsOutWithoutRefreshing() async throws {
        let (service, transport) = service { _, _ in (401, failure("auth.session_revoked"), [:]) }
        var events = service.session.events.makeAsyncIterator()

        let error = await #expect(throws: APIError.self) { try await service.deviceSessions() }
        #expect(error?.kind == .notAuthenticated)
        #expect(error?.errorCode == "auth.session_revoked")
        #expect(transport.requests.map(\.path) == ["/api/users/me/sessions"])
        #expect(await !service.session.isSignedIn)
        #expect(await events.next() == .signedOut(expired: true, revoked: true))
    }
}

import Foundation
import Testing
@testable import VomattCore

private let base = URL(string: "https://api.test")!

private func service(_ transport: StubTransport) -> VomattService {
    VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
}

@Suite("Community accounts")
struct CommunityTests {
    @Test func aProfileSaysWhenItIsACommunityAccount() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"id":"c1","username":"robotics","community":true,"mutualFollowersPreview":[{"id":"u2","username":"bob"}]}"#), [:])
        }
        let profile = try #require(try await service(transport).userProfile(username: "robotics"))
        #expect(profile.isCommunity)
        #expect(profile.mutualFollowersPreview.map(\.isCommunity) == [false])
    }

    @Test func searchAndFollowListsMarkCommunityAccounts() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"items":[{"id":"c1","username":"robotics","community":true},{"id":"u2","username":"bob","community":false}],"nextCursor":null}"#), [:])
        }
        let service = service(transport)
        #expect(try await service.searchUsers("ro").items.map(\.isCommunity) == [true, false])
        #expect(try await service.followers(username: "alice").items.map(\.isCommunity) == [true, false])
    }

    @Test func aPollSaysWhenItsOwnerIsACommunityAccount() async throws {
        let poll = #"{"id":"p1","title":"Q","creatorId":"c1","creatorUsername":"robotics","startTime":"2026-10-20T09:00:00+08:00","options":[]"#
        let transport = StubTransport { request, _ in
            (200, envelope(poll + (request.path == "/api/votes/p1" ? #","creatorCommunity":true}"# : "}")), [:])
        }
        let service = service(transport)
        #expect(try await service.poll(id: "p1")?.creatorIsCommunity == true)
        #expect(try await service.poll(id: "p2")?.creatorIsCommunity == false)
    }
}

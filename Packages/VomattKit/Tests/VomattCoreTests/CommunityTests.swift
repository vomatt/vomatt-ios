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

    @Test func listsTheViewersCommunitiesWithTheirRoleInEach() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"""
            [{"communityId":"c1","username":"sunrise_tower","displayName":"Sunrise Tower Committee","avatarUrl":"/api/avatars/a.jpg","role":"OWNER","locked":true},
             {"communityId":"c2","username":"robotics","role":"ANALYST"}]
            """#), [:])
        }
        let communities = try await service(transport).myCommunities()
        #expect(transport.requests.map { "\($0.method.rawValue) \($0.path)" } == ["GET /api/users/me/communities"])
        #expect(communities == [
            MyCommunity(id: "c1", username: "sunrise_tower", displayName: "Sunrise Tower Committee", avatarUrl: "/api/avatars/a.jpg", role: .owner, isLocked: true),
            MyCommunity(id: "c2", username: "robotics", role: .analyst),
        ])
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

/// Ported from vomatt-web `src/__tests__/features/communities/service.test.ts` and the failures
/// `CommunityInvitationCard.test.tsx` tells apart.
@Suite("Community invitations")
struct CommunityInvitationTests {
    @Test func readsOneInvitationWithItsCommunityAndInviter() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"""
            {"id":"i1","role":"EDITOR","expiresAt":"2026-11-21T10:00:00Z",
             "community":{"id":"c1","username":"robotics","displayName":"Robotics Club","avatarUrl":null,"community":true},
             "inviter":{"id":"u1","username":"ada","displayName":null,"avatarUrl":null},"locked":true,"member":false}
            """#), [:])
        }
        let invitation = try #require(try await service(transport).communityInvitation(id: "i/1"))
        #expect(transport.requests.map { "\($0.method.rawValue) \($0.path)" } == ["GET /api/community-invitations/i%2F1"])
        #expect(invitation == CommunityInvitationDetail(
            id: "i1", role: .editor, expiresAt: try #require(ISO8601DateFormatter().date(from: "2026-11-21T10:00:00Z")),
            community: UserSummary(id: "c1", username: "robotics", displayName: "Robotics Club", isCommunity: true),
            inviter: UserSummary(id: "u1", username: "ada"), isLocked: true, isMember: false
        ))
    }

    @Test func anInvitationWhoseInviterIsGoneStillReads() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"id":"i1","role":"ADMIN","expiresAt":"2026-11-21T10:00:00Z","community":{"id":"c1","username":"robotics"},"inviter":null,"member":true}"#), [:])
        }
        let invitation = try #require(try await service(transport).communityInvitation(id: "i1"))
        #expect(invitation.inviter == nil && invitation.isMember && !invitation.isLocked)
    }

    @Test func refusesAnInvitationWithoutItsCommunity() async {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"id":"i1","role":"EDITOR","expiresAt":"2026-11-21T10:00:00Z","inviter":null}"#), [:])
        }
        let error = await #expect(throws: APIError.self) { try await service(transport).communityInvitation(id: "i1") }
        #expect(error?.kind == .decoding)
    }

    @Test func anInvitationThatCanNoLongerBeAnsweredIsNil() async throws {
        let transport = StubTransport { _, _ in (404, failure("community.invitation.not_found"), [:]) }
        #expect(try await service(transport).communityInvitation(id: "i1") == nil)
    }

    @Test func anotherFailureToReadAnInvitationThrows() async {
        let transport = StubTransport { _, _ in (404, failure("user.not_found"), [:]) }
        let error = await #expect(throws: APIError.self) { try await service(transport).communityInvitation(id: "i1") }
        #expect(error?.isCommunityInvitationGone == false)
    }

    @Test func acceptingJoinsAndDecliningPosts() async throws {
        let transport = StubTransport { request, _ in
            (request.path ?? "").hasSuffix("/accept")
                ? (200, envelope(#"{"communityId":"c1","username":"sunrise","role":"EDITOR"}"#), [:])
                : (200, envelope(#"{"success":true}"#), [:])
        }
        let service = service(transport)
        #expect(try await service.acceptCommunityInvitation(id: "i1") == MyCommunity(id: "c1", username: "sunrise", role: .editor))
        try await service.declineCommunityInvitation(id: "i1")
        #expect(transport.requests.map { "\($0.method.rawValue) \($0.path)" } == [
            "POST /api/community-invitations/i1/accept", "POST /api/community-invitations/i1/decline",
        ])
    }

    @Test func answeringAnInvitationThatIsGoneSaysSo() async {
        let transport = StubTransport { _, _ in (404, failure("community.invitation.not_found"), [:]) }
        let service = service(transport)
        let accepted = await #expect(throws: APIError.self) { try await service.acceptCommunityInvitation(id: "i1") }
        let declined = await #expect(throws: APIError.self) { try await service.declineCommunityInvitation(id: "i1") }
        #expect(accepted?.isCommunityInvitationGone == true && declined?.isCommunityInvitationGone == true)
    }

    @Test func acceptingIntoALockedCommunityOrOverThePlanKeepsTheInvitationAndCarriesTheCode() async {
        for code in ["community.locked", "community.limit_reached"] {
            let transport = StubTransport { _, _ in (403, failure(code), [:]) }
            let error = await #expect(throws: APIError.self) { try await service(transport).acceptCommunityInvitation(id: "i1") }
            #expect(error?.errorCode == code && error?.isCommunityInvitationGone == false)
        }
    }
}

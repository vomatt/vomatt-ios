import Foundation
import HTTPTypes
import OpenAPIRuntime
import Testing
@testable import VomattCore

/// Answers requests from a handler and records them.
final class StubTransport: ClientTransport, @unchecked Sendable {
    struct Recorded: Sendable {
        let method: HTTPRequest.Method
        let path: String
        let authorization: String?
        let acceptLanguage: String?
        let body: String?
    }

    typealias Handler = @Sendable (HTTPRequest, String?) async throws -> (Int, String, [HTTPField.Name: String])

    private let lock = NSLock()
    private var log: [Recorded] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var requests: [Recorded] { lock.withLock { log } }

    func send(_ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String) async throws -> (HTTPResponse, HTTPBody?) {
        let text: String? = if let body { try await String(collecting: body, upTo: 1 << 20) } else { nil }
        lock.withLock {
            log.append(Recorded(
                method: request.method, path: request.path ?? "",
                authorization: request.headerFields[.authorization],
                acceptLanguage: request.headerFields[.acceptLanguage], body: text
            ))
        }
        let (status, json, headers) = try await handler(request, text)
        var fields = HTTPFields([HTTPField(name: .contentType, value: "application/json")])
        for (name, value) in headers { fields[name] = value }
        return (HTTPResponse(status: .init(code: status), headerFields: fields), HTTPBody(json))
    }
}

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

func envelope(_ data: String) -> String { #"{"success":true,"data":\#(data),"message":null,"errorCode":null,"error":null}"# }
func failure(_ code: String, _ message: String = "nope") -> String {
    #"{"success":false,"data":null,"message":"\#(message)","errorCode":"\#(code)","error":"\#(message)"}"#
}

private let base = URL(string: "https://api.test")!

@Suite("Service")
struct ServiceTests {
    @Test func decodesTheRealFeedPayload() async throws {
        let body = try fixture("listVotes")
        let transport = StubTransport { _, _ in (200, body, [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .zh }, transport: transport)

        let page = try await service.polls(limit: 2)
        let poll = try #require(page.items.first)
        #expect(poll.audience == .public)
        #expect(poll.voterVisibility == .signedIn)
        #expect(poll.options.map(\.displayOrder) == poll.options.map(\.displayOrder).sorted())
        #expect(poll.options.allSatisfy { $0.votes == nil })
        #expect(poll.turnout == 3)

        let request = try #require(transport.requests.first)
        #expect(request.path == "/api/votes?limit=2")
        #expect(request.authorization == nil)
        #expect(request.acceptLanguage == "zh-TW")
    }

    @Test func endedPayloadCarriesCounts() async throws {
        let body = try fixture("listVotesEnded")
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en },
                                    transport: StubTransport { _, _ in (200, body, [:]) })
        let page = try await service.polls(status: .ended, sort: .top, limit: 1)
        #expect(page.items.first?.inlineResults != nil)
        #expect(page.nextCursor != nil)
    }

    @Test func listQueryFollowsTheWebRules() async throws {
        let transport = StubTransport { _, _ in (200, envelope(#"{"items":[],"nextCursor":null}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        _ = try await service.polls(status: .ended, sort: .top, query: "a", limit: 99)
        _ = try await service.polls(sort: .closing, tag: "tech", query: " side ")
        let paths = transport.requests.map(\.path)
        // Ended lists take no sort; a 1-character search is no search; limit is clamped
        #expect(paths[0] == "/api/votes?status=ended&limit=50")
        #expect(paths[1] == "/api/votes?sort=closing&tag=tech&q=side&limit=10")
    }

    @Test func errorsCarryTheEnvelope() async throws {
        let transport = StubTransport { _, _ in (429, failure("vote.rate_limited", "Slow down"), [.retryAfter: "12"]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let error = await #expect(throws: APIError.self) { try await service.castBallot(pollId: "p", optionId: "o") }
        #expect(error?.isRateLimited == true)
        #expect(error?.retryAfter == 12)
        #expect(error?.errorCode == "vote.rate_limited")
        #expect(error?.message == "Slow down")
    }

    @Test func missingPollIsNil() async throws {
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en },
                                    transport: StubTransport { _, _ in (404, failure("vote.not_found"), [:]) })
        #expect(try await service.poll(id: "nope") == nil)
    }

    @Test func inviteOnlyOwnerComesFromTheCreatorEndpoint() async throws {
        let transport = StubTransport { _, _ in (200, envelope(#"{"username":"alice","avatarUrl":"bot:boba"}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let owner = try await service.inviteOnlyOwner(pollId: "p1")
        #expect(owner == PollOwner(username: "alice", avatarUrl: "bot:boba"))
        #expect(transport.requests.first?.path == "/api/votes/p1/creator")
    }

    @Test func ownerOfANonInviteOnlyPollIsNil() async throws {
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en },
                                    transport: StubTransport { _, _ in (404, failure("vote.not_found"), [:]) })
        #expect(try await service.inviteOnlyOwner(pollId: "nope") == nil)
    }

    @Test func createSendsTheContractShape() async throws {
        let poll = try firstPoll()
        let transport = StubTransport { _, _ in (201, envelope(poll), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let start = Date(timeIntervalSince1970: 1_791_766_800)
        _ = try await service.createPoll(PollInput(
            title: "Q", description: nil, options: ["A", "B"], startTime: start, endTime: start.addingTimeInterval(3600),
            voterVisibility: .nobody, audience: .public, invitees: InviteesInput(emails: ["x@y.co"])
        ))
        let body = try #require(transport.requests.first?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(json["audience"] as? String == "PUBLIC")
        #expect(json["voterVisibility"] as? String == "NOBODY")
        #expect(json["anonymous"] as? Bool == true)
        #expect(json["allowMultipleChoices"] as? Bool == false)
        #expect(json["inviteeEmails"] == nil)
        #expect(json["startTime"] as? String == "2026-10-12T01:00:00Z")
        let options = try #require(json["options"] as? [[String: Any]])
        #expect(options.map { $0["displayOrder"] as? Int } == [0, 1])
    }

    @Test func inviteListsUseTheInviteListPathsAndField() async throws {
        let transport = StubTransport { request, _ in
            request.path == "/api/invite-lists"
                ? (200, envelope(#"[{"id":"l1","name":"Book club","memberCount":2,"createdAt":"2026-10-09T15:20:31+08:00"}]"#), [:])
                : (200, envelope("[]"), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let lists = try await service.groups()
        #expect(lists.map(\.id) == ["l1"])
        _ = try await service.addInvitees(pollId: "p1", InviteesInput(groupIds: ["l1"]))
        let body = try #require(transport.requests.last?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(json["inviteListIds"] as? [String] == ["l1"])
        #expect(json["groupIds"] == nil)
    }

    private func firstPoll(_ extra: [String: Any] = [:]) throws -> String {
        let item = try #require(try JSONSerialization.jsonObject(with: Data(try fixture("listVotes").utf8)) as? [String: Any])
        var first = ((item["data"] as! [String: Any])["items"] as! [[String: Any]])[0]
        first.merge(extra) { $1 }
        return String(decoding: try JSONSerialization.data(withJSONObject: first), as: UTF8.self)
    }

    @Test func castSendsAnonymousOnlyWhenGiven() async throws {
        let poll = try firstPoll(["myOptionId": "o", "myBallotAnonymous": true])
        let transport = StubTransport { _, _ in (200, envelope(poll), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let cast = try await service.castBallot(pollId: "p", optionId: "o", anonymous: true)
        _ = try await service.castBallot(pollId: "p", optionId: "o")
        #expect(cast.myBallotAnonymous == true)
        let bodies = try transport.requests.map { try #require(JSONSerialization.jsonObject(with: Data(($0.body ?? "").utf8)) as? [String: Any]) }
        #expect(bodies[0]["anonymous"] as? Bool == true)
        #expect(bodies[1]["anonymous"] == nil)
    }

    // vomatt-api #44: 409 common.conflict means nothing was recorded; retry once
    @Test func aBusyBallotWriteIsRetriedOnce() async throws {
        let counter = Counter()
        let poll = try firstPoll()
        let transport = StubTransport { _, _ in
            await counter.increment()
            return await counter.value == 1 ? (409, failure("common.conflict"), [:]) : (200, envelope(poll), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        _ = try await service.castBallot(pollId: "p", optionId: "o")
        #expect(transport.requests.count == 2)
    }

    @Test func stillBusyAfterTheRetryThrows() async throws {
        let transport = StubTransport { _, _ in (409, failure("common.conflict", "Busy, try again"), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let error = await #expect(throws: APIError.self) { try await service.retractBallot(pollId: "p") }
        #expect(error?.isBusy == true)
        #expect(error?.message == "Busy, try again")
        #expect(transport.requests.count == 2)
    }

    // vomatt-api #50: 409 common.conflict on account deletion means nothing was deleted; retry once
    @Test func aBusyAccountDeletionIsRetriedOnce() async throws {
        let counter = Counter()
        let transport = StubTransport { request, _ in
            if request.method == .get { return (200, envelope(#"{"id":"u1","username":"alice"}"#), [:]) }
            await counter.increment()
            return await counter.value == 1 ? (409, failure("common.conflict"), [:]) : (200, envelope("null"), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.deleteMyAccount()
        #expect(transport.requests.map(\.method) == [.get, .delete, .delete])
    }

    @Test func exportReturnsTheDocumentAsJSON() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"exportedAt":"2026-10-23T10:00:00+08:00","preferences":{"visibility.location":"true"},"polls":[],"comments":[],"ballots":[]}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let data = try await service.exportMyData()
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect((json["preferences"] as? [String: String])?["visibility.location"] == "true")
        #expect(transport.requests.count == 1)
    }

    @Test func feedbackIsPostedAndRateLimited() async throws {
        let transport = StubTransport { _, _ in (201, envelope(#"{"id":"f1","success":true}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.sendFeedback("Please add dark mode.")
        let body = try #require(transport.requests.last?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(json["content"] as? String == "Please add dark mode.")
        #expect(transport.requests.last?.path.hasSuffix("/api/feedback") == true)

        let limited = StubTransport { _, _ in (429, failure("common.rate_limited", "Slow down"), [:]) }
        let capped = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: limited)
        let error = await #expect(throws: APIError.self) { try await capped.sendFeedback("again") }
        #expect(error?.isRateLimited == true)
    }

    @Test func aSecondExportInADayIsRateLimited() async throws {
        let transport = StubTransport { _, _ in (429, failure("common.rate_limited", "Slow down"), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let error = await #expect(throws: APIError.self) { try await service.exportMyData() }
        #expect(error?.isRateLimited == true)
    }

    @Test func profileCarriesTheBallotDefault() async throws {
        let transport = StubTransport { request, _ in
            if request.method == .patch { return (200, envelope(#"{"username":"alice"}"#), [:]) }
            return (200, envelope(#"{"id":"u1","username":"alice","anonymousBallotByDefault":true}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        #expect(try await service.myProfile().anonymousBallotByDefault == true)
        _ = try await service.updateProfile(anonymousBallotByDefault: false)
        let body = try #require(transport.requests.last?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(json.keys.sorted() == ["anonymousBallotByDefault"])
        #expect(json["anonymousBallotByDefault"] as? Bool == false)
    }

    @Test func profileCarriesNamesAndBirthday() async throws {
        let transport = StubTransport { request, _ in
            if request.method == .patch { return (200, envelope(#"{"username":"alice"}"#), [:]) }
            return (200, envelope(#"{"id":"u1","username":"alice","firstName":"Alice","lastName":"Chen","birthday":"1995-04-12","visibilitySettings":{"location":true}}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let me = try await service.myProfile()
        #expect(me.firstName == "Alice" && me.lastName == "Chen" && me.birthday == "1995-04-12")

        _ = try await service.updateProfile(firstName: "Alice", lastName: "", birthday: "1995-04-12")
        let body = try #require(transport.requests.last?.body)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        #expect(json.keys.sorted() == ["birthday", "firstName", "lastName"])
        #expect(json["birthday"] as? String == "1995-04-12")
        #expect(json["lastName"] as? String == "")
    }

    @Test func signInSaysWhetherTheAccountIsNew() async throws {
        let store = InMemoryTokenStore()
        let transport = StubTransport { request, _ in
            let path = request.path ?? ""
            if path.hasSuffix("/send-otp") { return (200, envelope(#"{"success":true}"#), [:]) }
            return (200, envelope(#"{"token":"a","refreshToken":"r","isNewUser":true}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: store, language: { .en }, transport: transport)
        try await service.requestOtp(email: "A@b.co")
        #expect(try await service.verifyOtp(email: "a@b.co", code: "123456") == true)
        #expect(transport.requests.map { $0.path ?? "" }.allSatisfy { !$0.contains("check-email") })
    }

    @Test func votersKeepNoChoiceWhenAnonymousBallotsExist() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"items":[{"userId":"u1","username":"alice","optionId":null}],"nextCursor":null}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let voters = try await service.voters(pollId: "p").items
        #expect(voters.map(\.username) == ["alice"] && voters.first?.optionId == nil)
    }

    @Test func blocksAreWrittenAndListedAcrossPages() async throws {
        let transport = StubTransport { request, _ in
            let path = request.path ?? ""
            if request.method != .get { return (200, envelope(#"{"success":true}"#), [:]) }
            if path.contains("cursor=c1") {
                return (200, envelope(#"{"items":[{"id":"u2","username":"bob"}],"nextCursor":null}"#), [:])
            }
            return (200, envelope(#"{"items":[{"id":"u1","username":"alice","displayName":"Alice","avatarUrl":"bot:boba"}],"nextCursor":"c1"}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.blockUser(id: "u1")
        try await service.unblockUser(id: "u1")
        let users = try await service.allBlockedUsers()
        #expect(users.map(\.username) == ["alice", "bob"])
        #expect(users.first?.avatarUrl == "bot:boba")
        let calls = transport.requests.map { "\($0.method.rawValue) \($0.path ?? "")" }
        #expect(calls.prefix(2) == ["POST /api/users/me/blocks/u1", "DELETE /api/users/me/blocks/u1"])
    }

    @Test func followsAreWrittenListedAndFeedPaged() async throws {
        let transport = StubTransport { request, _ in
            let path = request.path ?? ""
            if request.method != .get { return (200, envelope(#"{"success":true}"#), [:]) }
            if path.hasPrefix("/api/votes/following") {
                return (200, envelope(#"{"items":[],"nextCursor":null}"#), [:])
            }
            return (200, envelope(#"{"items":[{"id":"u1","username":"alice","displayName":"Alice","avatarUrl":"bot:boba"}],"nextCursor":null}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.followUser(id: "u1")
        try await service.unfollowUser(id: "u1")
        let users = try await service.allFollowedUsers()
        let feed = try await service.followingPolls()
        #expect(users.map(\.username) == ["alice"])
        #expect(feed.items.isEmpty && feed.nextCursor == nil)
        let calls = transport.requests.map { "\($0.method.rawValue) \($0.path ?? "")" }
        #expect(calls.prefix(2) == ["POST /api/users/me/follows/u1", "DELETE /api/users/me/follows/u1"])
        #expect(calls.last?.hasPrefix("GET /api/votes/following") == true)
    }

    @Test func profileCarriesViewerRelationAndFollowListsPage() async throws {
        let transport = StubTransport { request, _ in
            let path = request.path ?? ""
            if path.hasPrefix("/api/users/alice/follow") {
                return (200, envelope(#"{"items":[{"id":"u2","username":"bob"}],"nextCursor":"c2"}"#), [:])
            }
            return (200, envelope(#"{"id":"u1","username":"alice","isFollowing":true,"isBlocked":false}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let profile = try #require(try await service.userProfile(username: "alice"))
        let followers = try await service.followers(username: "alice")
        let following = try await service.following(username: "alice")
        #expect(profile.id == "u1" && profile.isFollowing == true && profile.isBlocked == false)
        #expect(followers.items.map(\.username) == ["bob"] && followers.nextCursor == "c2")
        #expect(following.items.count == 1)
        let calls = transport.requests.map { $0.path ?? "" }
        #expect(calls.contains { $0.hasPrefix("/api/users/alice/followers") })
        #expect(calls.contains { $0.hasPrefix("/api/users/alice/following") })
    }

    @Test func profileCarriesCountsAndMutualFollowers() async throws {
        let transport = StubTransport { request, _ in
            if (request.path ?? "").hasPrefix("/api/users/alice/mutual-followers") {
                return (200, envelope(#"{"items":[{"id":"u2","username":"bob","isFollowing":true,"followsYou":false}],"nextCursor":null}"#), [:])
            }
            return (200, envelope(#"""
            {"id":"u1","username":"alice","followersCount":12,"followingCount":3,"followsYou":true,
             "mutualFollowersCount":4,"mutualFollowersPreview":[{"id":"u2","username":"bob"}]}
            """#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let profile = try #require(try await service.userProfile(username: "alice"))
        #expect(profile.followersCount == 12 && profile.followingCount == 3 && profile.followsYou == true)
        #expect(profile.mutualFollowersCount == 4 && profile.mutualFollowersPreview.map(\.username) == ["bob"])
        let mutual = try await service.mutualFollowers(username: "alice")
        #expect(mutual.items.first?.isFollowing == true && mutual.items.first?.followsYou == false)
    }

    @Test func followListsCarryTheViewerRelation() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"items":[{"id":"u2","username":"bob","isFollowing":false,"followsYou":true}],"nextCursor":null}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let follower = try #require(try await service.followers(username: "alice").items.first)
        #expect(follower.isFollowing == false && follower.followsYou == true)
    }

    @Test func commentsCarryTheirFirstReplies() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"""
            {"items":[{"id":"c1","author":"june","text":"Hi","createdAt":"2026-10-26T09:30:00+08:00","replyCount":3,
              "replies":[{"id":"r1","parentId":"c1","author":"tom","text":"Yo","createdAt":"2026-10-26T09:31:00+08:00"}],
              "repliesNextCursor":"rc"}],"nextCursor":null}
            """#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let comment = try #require(try await service.comments(pollId: "p1").items.first)
        #expect(comment.replies.map(\.id) == ["r1"] && comment.repliesNextCursor == "rc" && comment.replyCount == 3)
    }

    @Test func sharingAPollSendsTheNativeChannelAndReturnsTheCount() async throws {
        let transport = StubTransport { _, _ in (200, envelope(#"{"shareCount":18}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let count = try await service.sharePoll(id: "p1")
        let sent = try #require(transport.requests.first)
        #expect(count == 18 && sent.method == .post && sent.path == "/api/votes/p1/share")
        #expect(try JSONSerialization.jsonObject(with: Data((sent.body ?? "").utf8)) as? [String: String] == ["channel": "NATIVE"])
    }

    @Test func reportingACommentSendsTheReasonAndTrimmedNote() async throws {
        let transport = StubTransport { _, _ in (200, envelope(#"{"success":true}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.reportComment(pollId: "p1", commentId: "c1", reason: .harassment, note: "  rude  ")
        try await service.reportComment(pollId: "p1", commentId: "c1", reason: .spam, note: "  ")
        let sent = transport.requests
        #expect(sent[0].method == .post && sent[0].path == "/api/votes/p1/comments/c1/report")
        let first = try JSONSerialization.jsonObject(with: Data((sent[0].body ?? "").utf8)) as? [String: String]
        let second = try JSONSerialization.jsonObject(with: Data((sent[1].body ?? "").utf8)) as? [String: String]
        #expect(first == ["reason": "HARASSMENT", "note": "rude"])
        #expect(second == ["reason": "SPAM"])
    }

    @Test func mentionsDefaultToOnWhenTheAPIOmitsThem() async throws {
        let transport = StubTransport { _, _ in (200, envelope(#"{"resultsIn":true,"invitations":true,"comments":true,"closingSoon":false}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        _ = try await service.updateNotificationPreferences(mentions: false)
        #expect(try await service.notificationPreferences().mentions)
        #expect(transport.requests[0].body.map { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Bool] } == ["mentions": false])
    }

    @Test func reportingAPollSendsTheReasonAndTrimmedNote() async throws {
        let transport = StubTransport { _, _ in (200, envelope(#"{"success":true}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.reportPoll(id: "p1", reason: .hate, note: "  Slurs ")
        let sent = try #require(transport.requests.first)
        #expect(sent.method == .post && sent.path == "/api/votes/p1/report")
        #expect(try JSONSerialization.jsonObject(with: Data((sent.body ?? "").utf8)) as? [String: String] == ["reason": "HATE", "note": "Slurs"])
    }

    @Test func reportingYourOwnPollCarriesTheErrorCode() async throws {
        let transport = StubTransport { _, _ in (400, failure("vote.report.self"), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let error = await #expect(throws: APIError.self) { try await service.reportPoll(id: "p1", reason: .other) }
        #expect(error?.errorCode == "vote.report.self")
    }

    @Test func bookmarksArePutDeletedAndListed() async throws {
        let transport = StubTransport { request, _ in
            request.method == .get
                ? (200, envelope(#"{"items":[],"nextCursor":null}"#), [:])
                : (200, envelope(#"{"success":true}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.setBookmark(pollId: "p1", bookmarked: true)
        try await service.setBookmark(pollId: "p1", bookmarked: false)
        _ = try await service.bookmarkedPolls(cursor: "abc", limit: 5)
        let calls = transport.requests.map { "\($0.method.rawValue) \($0.path)" }
        #expect(calls == ["PUT /api/votes/p1/bookmark", "DELETE /api/votes/p1/bookmark", "GET /api/votes/bookmarked?cursor=abc&limit=5"])
    }

    @Test func aPollSaysWhetherTheViewerSavedIt() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"id":"p1","title":"Q","creatorId":"u1","creatorUsername":"mei","startTime":"2026-10-20T09:00:00+08:00","bookmarked":true,"options":[]}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        #expect(try await service.poll(id: "p1")?.bookmarked == true)
    }

    @Test func topicsAreFollowedUnfollowedAndListed() async throws {
        let transport = StubTransport { request, _ in
            request.method == .get
                ? (200, envelope(#"[{"id":"t1","name":"Food","slug":"food"}]"#), [:])
                : (200, envelope(#"{"success":true}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.setTagFollow(tagId: "t1", following: true)
        try await service.setTagFollow(tagId: "t1", following: false)
        let tags = try await service.followedTags()
        #expect(tags == [Tag(id: "t1", name: "Food", slug: "food")])
        let calls = transport.requests.map { "\($0.method.rawValue) \($0.path)" }
        #expect(calls == ["PUT /api/tags/t1/follow", "DELETE /api/tags/t1/follow", "GET /api/tags/following"])
    }

    @Test func aDeletedAccountIsToldApartFromOtherFailures() async throws {
        let gone = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en },
                                 transport: StubTransport { _, _ in (404, failure("user.not_found"), [:]) })
        let error = await #expect(throws: APIError.self) { try await gone.myProfile() }
        #expect(error?.isAccountGone == true)
        let down = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en },
                                 transport: StubTransport { _, _ in (500, failure("common.internal_error"), [:]) })
        let other = await #expect(throws: APIError.self) { try await down.myProfile() }
        #expect(other?.isAccountGone == false)
    }

    @Test func theFeedDecodesEachKindAndPages() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"""
            {"items":[
              {"id":"comment_1","kind":"COMMENT","createdAt":"2026-10-26T09:30:00+08:00","read":false,
               "actor":{"id":"u2","username":"bob","isFollowing":false,"followsYou":true},
               "poll":{"id":"p1","title":"Ramen?","status":"OPEN","turnout":3,"myOptionId":null,"winningOptionIds":null,"tie":null},
               "comment":{"id":"r1","parentId":"c1","excerpt":"Tonkotsu"}},
              {"id":"result_p2","kind":"RESULT","createdAt":"2026-10-25T09:30:00+08:00","read":true,"actor":null,"comment":null,
               "poll":{"id":"p2","title":"Tea?","status":"ENDED","turnout":9,"myOptionId":"o1","winningOptionIds":["o1"],
                       "winningOptionLabels":["Oolong"],"tie":false}},
              {"id":"followed_u3","kind":"FOLLOWED","createdAt":"2026-10-24T09:30:00+08:00","read":false,
               "actor":{"id":"u3","username":"cy","isFollowing":false,"followsYou":true},"poll":null,"comment":null}
            ],"nextCursor":"n2"}
            """#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let page = try await service.notifications(cursor: "n1", limit: 20)
        #expect(page.nextCursor == "n2")
        #expect(page.items.map(\.kind) == [.comment, .result, .followed])
        #expect(page.items[0].comment?.parentId == "c1" && page.items[0].actor?.followsYou == true && page.items[0].poll?.viewerWon == nil)
        #expect(page.items[1].read && page.items[1].poll?.viewerWon == true && page.items[1].poll?.winningOptionLabels == ["Oolong"])
        #expect(transport.requests[0].path.contains("cursor=n1"))
    }

    @Test func aNotificationKindOrCategoryTheAppDoesNotKnowLeavesTheRestOfTheFeed() async throws {
        let actor = #"{"id":"u2","username":"bob"}"#
        let poll = #"{"id":"p1","title":"Ramen?","status":"OPEN","turnout":3}"#
        let comment = #"{"id":"c1","parentId":null,"excerpt":"@mei try Nagi"}"#
        let transport = StubTransport { _, _ in
            (200, envelope(#"""
            {"items":[
              {"id":"future_1","kind":"POLL_STARTED","category":"SCHEDULE","createdAt":"2026-10-27T09:30:00+08:00","read":false,"poll":\#(poll)},
              {"id":"mention_c1","kind":"MENTION","category":"CONVERSATION","createdAt":"2026-10-26T09:30:00+08:00","read":false,
               "actor":\#(actor),"poll":\#(poll),"comment":\#(comment)},
              {"id":"like_c1","kind":"LIKE","category":"LIKE","createdAt":"2026-10-26T08:30:00+08:00","read":false,
               "actor":\#(actor),"poll":\#(poll),"comment":\#(comment)},
              {"id":"comment_c2","kind":"COMMENT","category":"THREADS","createdAt":"2026-10-25T09:30:00+08:00","read":true,
               "actor":\#(actor),"poll":\#(poll),"comment":\#(comment)},
              {"kind":"COMMENT","createdAt":"2026-10-24T09:30:00+08:00","read":true}
            ],"nextCursor":"n2"}
            """#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let page = try await service.notifications()
        // A new kind, LIKE (no row on the web yet), an unknown category and an item without an id are each left out or ignored
        #expect(page.items.map(\.id) == ["mention_c1", "comment_c2"])
        #expect(page.items.map(\.kind) == [.mention, .comment])
        #expect(page.items[0].comment?.excerpt == "@mei try Nagi" && page.items[0].actor?.username == "bob")
        #expect(page.nextCursor == "n2")
    }

    @Test func notificationsAreReadOneByOneOrAllAtOnce() async throws {
        let transport = StubTransport { _, _ in (200, envelope(#"{"success":true}"#), [:]) }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        try await service.markNotificationRead(id: "comment_1")
        try await service.markAllNotificationsRead()
        let calls = transport.requests.map { "\($0.method.rawValue) \($0.path ?? "")" }
        #expect(calls == ["POST /api/notifications/comment_1/read", "POST /api/notifications/read-all"])
    }

    @Test func notificationPreferencesChangeOnlyTheGivenSwitches() async throws {
        let transport = StubTransport { _, _ in
            (200, envelope(#"{"resultsIn":true,"invitations":true,"comments":false,"mentions":false,"likes":true,"closingSoon":true}"#), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport)
        let current = try await service.notificationPreferences()
        let updated = try await service.updateNotificationPreferences(closingSoon: true)
        #expect(current == updated && updated.closingSoon && !updated.comments && !updated.mentions)
        #expect(transport.requests[1].method == .patch && transport.requests[1].path == "/api/users/me/notification-preferences")
        #expect(transport.requests[1].body?.contains("closingSoon") == true && transport.requests[1].body?.contains("comments") == false)
    }
}

@Suite("Session")
struct SessionTests {
    private func tokens(_ n: Int, exp: TimeInterval = Date.now.timeIntervalSince1970 + 3600) -> AuthTokens {
        AuthTokens(accessToken: TokenClaimTests.token(sub: "user-1", exp: exp), refreshToken: "refresh-\(n)")
    }

    @Test func refreshesOnceForConcurrentCallers() async throws {
        let counter = Counter()
        let rotated = tokens(2)
        let session = Session(store: InMemoryTokenStore(tokens(1, exp: Date.now.timeIntervalSince1970 + 10))) { token in
            await counter.increment()
            #expect(token == "refresh-1")
            try? await Task.sleep(for: .milliseconds(50))
            return .ok(rotated)
        }
        async let a = session.accessToken()
        async let b = session.accessToken()
        async let c = session.accessToken()
        let results = await [a, b, c]
        #expect(results.allSatisfy { $0 == rotated.accessToken })
        #expect(await counter.value == 1)
        #expect(await session.refreshToken == "refresh-2")
    }

    @Test func rejectionEndsTheSession() async throws {
        let store = InMemoryTokenStore(tokens(1))
        let session = Session(store: store) { _ in .rejected(suspicious: false) }
        let token = try #require(await session.accessToken())
        #expect(await session.accessTokenAfterRejection(of: token) == nil)
        #expect(await !session.isSignedIn)
        #expect(store.load() == nil)
        var events = session.events.makeAsyncIterator()
        #expect(await events.next() == .signedOut(expired: true))
    }

    @Test func unavailableKeepsTheSession() async throws {
        let session = Session(store: InMemoryTokenStore(tokens(1, exp: Date.now.timeIntervalSince1970 + 10))) { _ in .unavailable }
        #expect(await session.accessToken() != nil)
        #expect(await session.isSignedIn)
    }

    /// F1 in .claude/skills/verify-session-refresh: a waiter from an earlier refresh must not clear the
    /// record of a newer in-flight refresh that happens to carry the same refresh token, or the next
    /// caller starts a duplicate and the backend ends the sign-in. Sign-out/sign-in with the same pair
    /// is the deterministic way to put a newer refresh behind an older waiter.
    @Test func aStaleWaiterDoesNotClearANewerRefresh() async throws {
        let calls = Counter()
        let gates = [Gate(), Gate()]
        let rotated = tokens(2)
        let session = Session(store: InMemoryTokenStore(tokens(1, exp: Date.now.timeIntervalSince1970 + 10))) { _ in
            let n = await calls.increment()
            switch n {
            case 1: await gates[0].wait(); return .unavailable
            case 2: await gates[1].wait(); return .ok(rotated)
            default: Issue.record("a third refresh was started"); return .unavailable
            }
        }
        async let a = session.accessToken()
        try await eventually { await calls.value == 1 }
        await session.signOut()
        await session.signIn(tokens(1, exp: Date.now.timeIntervalSince1970 + 10))
        async let c = session.accessToken()
        try await eventually { await calls.value == 2 }
        await gates[0].open()
        #expect(await a != nil) // unavailable: keeps the (re-signed-in) session's token
        async let d = session.accessToken() // must join the second refresh, not start a third
        await gates[1].open()
        let late = await [c, d]
        #expect(late.allSatisfy { $0 == rotated.accessToken })
        #expect(await calls.value == 2)
    }

    /// F2: a refresh that completes after signOut() must not bring the session back.
    @Test func aRefreshFinishingAfterSignOutIsDropped() async throws {
        let started = Counter()
        let gate = Gate()
        let store = InMemoryTokenStore(tokens(1))
        let session = Session(store: store) { _ in
            _ = await started.increment()
            await gate.wait()
            return .ok(tokens(2))
        }
        let token = try #require(await session.accessToken())
        async let retry = session.accessTokenAfterRejection(of: token)
        try await eventually { await started.value == 1 }
        await session.signOut()
        await gate.open()
        #expect(await retry == nil)
        #expect(await !session.isSignedIn)
        #expect(store.load() == nil)
    }

    @Test func aStaleRejectionReusesTheNewerToken() async throws {
        let current = tokens(1)
        let session = Session(store: InMemoryTokenStore(current)) { _ in Issue.record("should not refresh"); return .unavailable }
        #expect(await session.accessTokenAfterRejection(of: "an-older-token") == current.accessToken)
        #expect(await session.userId == "user-1")
    }

    @Test func retriesA401AfterRefreshing() async throws {
        let fresh = tokens(2)
        let transport = StubTransport { request, _ in
            if request.path == "/api/auth/refresh" {
                return (200, envelope(#"{"token":"\#(fresh.accessToken)","refreshToken":"refresh-2"}"#), [:])
            }
            if request.headerFields[.authorization] == "Bearer \(fresh.accessToken)" {
                return (200, envelope(#"{"count":4}"#), [:])
            }
            return (401, failure("auth.token.expired"), [:])
        }
        let store = InMemoryTokenStore(tokens(1))
        let service = VomattService(baseURL: base, tokenStore: store, language: { .en }, transport: transport)
        #expect(try await service.unreadCount() == 4)
        #expect(transport.requests.map(\.path) == ["/api/notifications/unread-count", "/api/auth/refresh", "/api/notifications/unread-count"])
        // The refresh call itself never carries the access token
        #expect(transport.requests[1].authorization == nil)
        #expect(store.load()?.refreshToken == "refresh-2")
    }

    @Test func aDeadSessionSurfacesAsNotAuthenticated() async throws {
        let transport = StubTransport { request, _ in
            request.path == "/api/auth/refresh" ? (401, failure("auth.refresh_token.invalid"), [:]) : (401, failure("auth.token.invalid"), [:])
        }
        let service = VomattService(baseURL: base, tokenStore: InMemoryTokenStore(tokens(1)), language: { .en }, transport: transport)
        let error = await #expect(throws: APIError.self) { try await service.myProfile() }
        #expect(error?.kind == .notAuthenticated)
        #expect(await !service.session.isSignedIn)
    }
}

actor Counter {
    private(set) var value = 0
    @discardableResult func increment() -> Int { value += 1; return value }
}

/// Holds async callers until opened.
actor Gate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if opened { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        opened = true
        for waiter in waiters { waiter.resume() }
        waiters = []
    }
}

/// Polls `condition` for up to a second.
func eventually(_ condition: () async -> Bool) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("condition not met in time")
}

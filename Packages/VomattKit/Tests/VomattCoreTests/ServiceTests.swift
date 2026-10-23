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

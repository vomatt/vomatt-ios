import Foundation
import Testing
@testable import VomattCore

private let base = URL(string: "https://api.test")!
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let hour: TimeInterval = 3600

private func iso(_ date: Date) -> String { date.ISO8601Format(.iso8601) }

private func poll(_ id: String, endingIn hours: Double, extra: String = "") -> String {
    #"{"id":"\#(id)","title":"Q","creatorId":"u1","creatorUsername":"mei","startTime":"\#(iso(now - 48 * hour))","endTime":"\#(iso(now + hours * hour))","options":[]\#(extra)}"#
}

private func page(_ polls: [String], _ next: String? = nil) -> String {
    envelope(#"{"items":[\#(polls.joined(separator: ","))],"nextCursor":\#(next.map { "\"\($0)\"" } ?? "null")}"#)
}

/// Answers each request with the next body, and the last body after that.
private func service(_ bodies: String...) -> (VomattService, StubTransport) {
    let calls = Counter()
    let transport = StubTransport { _, _ in (200, bodies[min(await calls.increment(), bodies.count) - 1], [:]) }
    return (VomattService(baseURL: base, tokenStore: InMemoryTokenStore(), language: { .en }, transport: transport), transport)
}

@Suite("Home feeds")
struct HomeFeedTests {
    private let voted = poll("poll-1", endingIn: -2, extra: #","myOptionId":"opt-1""#)
    private let notVoted = poll("poll-8", endingIn: -2)

    @Test func resultsInKeepsOnlyTheEndedPollsTheViewerVotedIn() async throws {
        let (service, transport) = service(page([voted, notVoted], "c2"))
        let result = try await service.resultsInFeed()
        #expect(result.items.map(\.id) == ["poll-1"])
        #expect(result.nextCursor == "c2")
        #expect(transport.requests.map(\.path) == ["/api/votes/my?status=ended&limit=10"])
    }

    @Test func resultsInKeepsAPollWhoseAnonymousBallotWasSealed() async throws {
        let sealed = poll("poll-7", endingIn: -30, extra: #","myBallotAnonymous":true"#)
        let (service, _) = service(page([sealed, notVoted]))
        #expect(try await service.resultsInFeed().items.map(\.id) == ["poll-7"])
    }

    @Test func resultsInReadsPastPagesWithNoVotedPollSoAPageIsEmptyOnlyAtTheEnd() async throws {
        let (service, transport) = service(page([notVoted], "c2"), page([voted], "c3"))
        let result = try await service.resultsInFeed(cursor: "c1")
        #expect(result.items.map(\.id) == ["poll-1"])
        #expect(result.nextCursor == "c3")
        #expect(transport.requests.last?.path == "/api/votes/my?status=ended&cursor=c2&limit=10")
    }

    @Test func closingSoonAsksForOpenPollsClosingSoonestFirst() async throws {
        let (service, transport) = service(page([poll("a", endingIn: 2)], "c2"))
        let result = try await service.closingSoonFeed(now: now)
        #expect(result.items.map(\.id) == ["a"])
        #expect(result.nextCursor == "c2")
        #expect(transport.requests.map(\.path) == ["/api/votes?sort=closing&limit=10"])
    }

    @Test func closingSoonEndsAtTheFirstPollWithMoreThanADayLeft() async throws {
        let (service, _) = service(page([poll("a", endingIn: 2), poll("b", endingIn: 30)], "c2"))
        let result = try await service.closingSoonFeed(now: now)
        #expect(result.items.map(\.id) == ["a"])
        #expect(result.nextCursor == nil)
    }

    @Test(arguments: [
        (HomeFeed.forYou, "/api/votes?tag=work&limit=10"),
        (.following, "/api/votes/following?limit=10"),
        (.resultsIn, "/api/votes/my?status=ended&limit=10"),
        (.closingSoon, "/api/votes?sort=closing&limit=10"),
    ])
    func eachFeedReadsItsList(feed: HomeFeed, path: String) async throws {
        let (service, transport) = service(page([]))
        _ = try await service.feed(feed, cursor: nil, tag: "work")
        #expect(transport.requests.first?.path == path)
    }
}

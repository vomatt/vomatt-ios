import Foundation
import Testing
@testable import VomattCore

// Cases ported from vomatt-web's src/__tests__/hooks/useBallot.test.ts ("useBallot anonymity")
@Suite("Ballot anonymity")
struct BallotAnonymityTests {
    @Test func startsAFirstVoteFromTheAccountDefault() {
        let anonymity = BallotAnonymity(ballot: nil)
        #expect(anonymity.shown(hasBallot: false, accountDefault: true) == true)
        #expect(anonymity.forFirstVote(accountDefault: true) == true)
    }

    @Test func leavesAFirstVoteToTheAPIWhenTheDefaultIsUnknown() {
        let anonymity = BallotAnonymity(ballot: nil)
        #expect(anonymity.shown(hasBallot: false, accountDefault: nil) == false)
        #expect(anonymity.forFirstVote(accountDefault: nil) == nil)
    }

    @Test func holdsAChoiceMadeBeforeVotingAndCastsItWithTheVote() {
        var anonymity = BallotAnonymity(ballot: nil)
        anonymity.choose(true)
        #expect(anonymity.shown(hasBallot: false, accountDefault: false) == true)
        #expect(anonymity.forFirstVote(accountDefault: false) == true)
    }

    @Test func keepsAChoiceMadeBeforeVotingWhenTheVoteFails() {
        var anonymity = BallotAnonymity(ballot: nil)
        anonymity.choose(true)
        // A failed vote never reports `voted`
        #expect(anonymity.shown(hasBallot: false, accountDefault: nil) == true)
    }

    @Test func showsTheBallotsOwnFlagOnceCast() {
        var anonymity = BallotAnonymity(ballot: nil)
        anonymity.voted(true)
        #expect(anonymity.shown(hasBallot: true, accountDefault: false) == true)
    }

    @Test func goesBackToTheAccountDefaultOnceTheBallotIsWithdrawn() {
        let anonymity = BallotAnonymity(ballot: true)
        #expect(anonymity.shown(hasBallot: false, accountDefault: false) == false)
    }

    @Test func startsAVoteAfterWithdrawingFromTheAccountDefaultNotTheEarlierChoice() {
        var anonymity = BallotAnonymity(ballot: nil)
        anonymity.choose(true)
        anonymity.voted(true)
        #expect(anonymity.shown(hasBallot: false, accountDefault: false) == false)
        #expect(anonymity.forFirstVote(accountDefault: false) == false)
    }
}

// vomatt-web's Results caption and the account's ballotOutcome, read from result rows
@Suite("Results summary")
struct ResultsSummaryTests {
    private func rows(_ a: Int, _ b: Int) -> [ResultRow] {
        [ResultRow(id: "a", text: "A", votes: a), ResultRow(id: "b", text: "B", votes: b)]
    }

    @Test func saysWhatTheRowsDecided() {
        #expect(Results.summary(rows(3, 1)) == .won("A"))
        #expect(Results.summary(rows(2, 2)) == .tie(["A", "B"]))
        #expect(Results.summary(rows(0, 0)) == .none)
    }

    @Test func saysHowTheViewersPickFared() {
        #expect(Results.outcome(of: "a", in: rows(3, 1)) == .won)
        #expect(Results.outcome(of: "b", in: rows(3, 1)) == .lost)
        #expect(Results.outcome(of: "b", in: rows(2, 2)) == .tied)
    }

    @Test func hasNoOutcomeWithoutAPick() {
        #expect(Results.outcome(of: nil, in: rows(3, 1)) == nil)
        #expect(Results.outcome(of: "gone", in: rows(3, 1)) == nil)
    }
}

/// Ported from vomatt-web `src/__tests__/features/polls/MoreFromAuthor.test.tsx`.
@Suite("More from the author")
struct MoreFromAuthorTests {
    private static let now = ISO8601DateFormatter().date(from: "2026-10-28T02:00:00Z")!
    private static let hour: TimeInterval = 3600

    private static func localizer() throws -> Localizer {
        let locales = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../App/Resources/Locales").standardized
        let strings = try Localizer.flatten(json: Data(contentsOf: locales.appending(path: "en.json")))
        return Localizer(language: .en, strings: strings, fallback: strings)
    }

    private func poll(id: String = "poll-2", endIn hours: Double, participants: Int) -> Poll {
        Poll(
            id: id, title: "Fortnightly street cleaning?", creatorId: "user-1", creatorUsername: "amira",
            createdAt: Self.now.addingTimeInterval(-96 * Self.hour), startTime: Self.now.addingTimeInterval(-96 * Self.hour),
            endTime: Self.now.addingTimeInterval(hours * Self.hour), participantCount: participants, options: []
        )
    }

    private func meta(_ poll: Poll) throws -> String {
        MoreFromAuthor.meta(poll, now: Self.now, t: try Self.localizer(), dates: DateFormatting(language: .en))
    }

    @Test func endedPollSaysEndedWithItsTurnout() throws {
        #expect(try meta(poll(endIn: -1, participants: 611)) == "ended · 611 voted")
    }

    @Test func openPollSaysWhenItEndsBesideItsTurnout() throws {
        #expect(try meta(poll(endIn: 2 + 1.0 / 60, participants: 96)) == "ends in 2h · 96 voted")
    }

    @Test func picksTwoPollsOtherThanThisOne() {
        let polls = ["p1", "p2", "p3"].map { poll(id: $0, endIn: 1, participants: 0) }
        #expect(MoreFromAuthor.pick(polls, excluding: "p2").map(\.id) == ["p1", "p3"])
    }
}

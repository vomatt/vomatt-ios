import Foundation
import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/features/profiles/lists.test.ts`.
@Suite("Profile lists")
struct ProfileListsTests {
    enum State { case scheduled, open, ended, cancelled }

    private static let now = date("2026-10-05T12:00:00Z")

    private static func date(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    private func poll(
        _ id: String, votes: [String: Int]? = nil, state: State = .open, myOptionId: String? = nil,
        creatorId: String = "other", startTime: String = "2026-10-01T00:00:00Z"
    ) -> Poll {
        let start = Self.date(state == .scheduled ? "2026-10-08T00:00:00Z" : startTime)
        let end: Date = switch state {
        case .scheduled, .open: Self.date("2026-10-09T00:00:00Z")
        case .ended: Self.date("2026-10-04T00:00:00Z")
        case .cancelled: start
        }
        return Poll(
            id: id, title: id, votingActive: state == .open, creatorId: creatorId, creatorUsername: creatorId,
            createdAt: Self.date("2026-10-01T00:00:00Z"), startTime: start, endTime: end, myOptionId: myOptionId,
            options: ["a", "b", "c"].map { key in PollOption(id: key, text: key.uppercased(), votes: votes.map { $0[key] ?? 0 }) }
        )
    }

    @Test func askedPutsScheduledAndOpenPollsBeforeEndedOnes() {
        let split = ProfileLists.splitAsked([poll("e", state: .ended), poll("s", state: .scheduled), poll("o")], at: Self.now)
        #expect(split.open.map(\.id) == ["s", "o"])
        #expect(split.ended.map(\.id) == ["e"])
    }

    @Test func votedSeparatesSealedBallotsFromDecidedOnes() {
        let split = ProfileLists.splitVoted([poll("o", myOptionId: "a"), poll("e", state: .ended, myOptionId: "a")], at: Self.now)
        #expect(split.sealed.map(\.id) == ["o"])
        #expect(split.decided.map(\.id) == ["e"])
    }

    @Test func votedKeepsPollsTheOwnerVotedInButDidNotAsk() {
        let polls = [poll("mine", myOptionId: "a", creatorId: "me"), poll("voted", myOptionId: "b"), poll("invited")]
        #expect(ProfileLists.voted(polls, viewerId: "me").map(\.id) == ["voted"])
    }

    @Test func askedKeepsTheOwnersPollsMostRecentlyOpenedFirst() {
        let older = poll("older", creatorId: "me", startTime: "2026-09-01T00:00:00Z")
        let polls = [older, poll("voted", myOptionId: "b"), poll("mine", myOptionId: "a", creatorId: "me")]
        #expect(ProfileLists.asked(polls, viewerId: "me").map(\.id) == ["mine", "older"])
    }

    @Test func picksWonIsTheShareOfDecidedBallotsThatWonOutright() {
        let polls = [
            poll("won", votes: ["a": 3, "b": 1], state: .ended, myOptionId: "a"),
            poll("lost", votes: ["a": 3, "b": 1], state: .ended, myOptionId: "b"),
            poll("tied", votes: ["a": 2, "b": 2], state: .ended, myOptionId: "a"),
            poll("won2", votes: ["c": 5], state: .ended, myOptionId: "c"),
        ]
        #expect(ProfileLists.picksWonRate(polls, at: Self.now) == 50)
    }

    @Test func picksWonLeavesOutOpenHiddenAndCancelledPolls() {
        let polls = [
            poll("open", votes: ["a": 1], myOptionId: "a"),
            poll("hidden", state: .ended, myOptionId: "a"),
            poll("cancelled", votes: ["a": 1], state: .cancelled, myOptionId: "a"),
        ]
        #expect(ProfileLists.picksWonRate(polls, at: Self.now) == nil)
    }

    @Test func endedSummaryNamesOneWinner() {
        #expect(ProfileLists.endedSummary(poll("p", votes: ["a": 3, "b": 1], state: .ended)) == .won("A"))
    }

    @Test func endedSummaryNamesEveryOptionTiedForFirst() {
        #expect(ProfileLists.endedSummary(poll("p", votes: ["a": 2, "b": 2], state: .ended)) == .tie(["A", "B"]))
    }

    @Test func endedSummarySaysNothingWithNoVotesHiddenCountsOrACancelledPoll() {
        #expect(ProfileLists.endedSummary(poll("p", votes: [:], state: .ended)) == .none)
        #expect(ProfileLists.endedSummary(poll("p", state: .ended)) == .none)
        #expect(ProfileLists.endedSummary(poll("p", votes: ["a": 1], state: .cancelled)) == .none)
    }
}

/// Ported from the meta cases of vomatt-web `src/__tests__/features/polls/DraftList.test.tsx`:
/// Wednesday 28 October 2026, 10:00 in Taipei.
@Suite("Draft meta")
struct DraftMetaTests {
    private static let taipei = TimeZone(identifier: "Asia/Taipei")!
    private static let now = try! Date("2026-10-28T02:00:00Z", strategy: .iso8601)

    private func meta(savedAt: String, form: PollForm) throws -> String {
        let locales = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../App/Resources/Locales").standardized
        let strings = try Localizer.flatten(json: Data(contentsOf: locales.appending(path: "en.json")))
        let draft = PollDraft(savedAt: try Date(savedAt, strategy: .iso8601), form: form)
        return draft.meta(t: Localizer(language: .en, strings: strings), dates: DateFormatting(language: .en, timeZone: Self.taipei), now: Self.now)
    }

    @Test func saysWhenItWasSavedItsFilledOptionsAndAMissingEnd() throws {
        let form = PollForm(title: "Rename the club?", options: ["A", "B", "C", " "], endTime: nil)
        #expect(try meta(savedAt: "2026-10-27T09:00:00Z", form: form) == "Saved yesterday · 3 options · no end date yet")
    }

    @Test func saysOnlyWhenABlankDraftWithAnEndWasSaved() throws {
        let form = PollForm(endTime: try Date("2026-11-01T12:00:00Z", strategy: .iso8601))
        #expect(try meta(savedAt: "2026-10-20T09:00:00Z", form: form) == "Saved Oct 20")
    }
}

import Testing
@testable import VomattCore

// The unlisted count of vomatt-web's VotersDialog (src/features/polls/components/VoterList.tsx)

private func voter(_ id: String, chose optionId: String?) -> Voter {
    Voter(userId: id, username: id, optionId: optionId)
}

private func list(
    _ voters: [Voter], option: String = "a", votes: Int, participants: Int, complete: Bool = true, mine: String? = nil
) -> VoterList {
    VoterList(voters: voters, optionId: option, votes: votes, participants: participants, complete: complete, myAnonymousOptionId: mine)
}

@Suite("Voter list")
struct VoterListTests {
    @Test func countsTheOptionsVotersTheListLeavesOut() {
        let result = list([voter("u1", chose: "a"), voter("u2", chose: "b")], votes: 3, participants: 5)
        #expect(result.listed.map(\.userId) == ["u1"])
        #expect(result.unlisted == 2)
        #expect(!result.includesMine)
    }

    @Test func withChoicesHiddenCountsAgainstEveryoneWhoTookPart() {
        let result = list([voter("u1", chose: nil), voter("u2", chose: nil)], votes: 1, participants: 4)
        #expect(result.choicesHidden)
        #expect(result.listed.count == 2)
        #expect(result.unlisted == 2)
    }

    @Test func countsNothingUntilEveryPageIsIn() {
        #expect(list([voter("u1", chose: "a")], votes: 3, participants: 3, complete: false).unlisted == 0)
    }

    @Test func neverCountsBelowZero() {
        #expect(list([voter("u1", chose: "a"), voter("u2", chose: "a")], votes: 1, participants: 2).unlisted == 0)
    }

    @Test func includesTheViewersAnonymousBallotOnItsOwnOption() {
        #expect(list([], votes: 1, participants: 1, mine: "a").includesMine)
        #expect(!list([], votes: 1, participants: 1, mine: "b").includesMine)
        #expect(list([voter("u1", chose: nil)], votes: 1, participants: 2, mine: "b").includesMine)
    }
}

import Foundation

/// Who one option's voter list shows (the web's `VotersDialog`). While an Anonymous Ballot is in the Poll the API
/// withholds every choice, so the list shows everyone who took part instead. Anonymous Ballots and removed accounts
/// are counted but never listed.
public struct VoterList: Equatable, Sendable {
    /// Choices are withheld: `listed` is everyone who took part, not who chose the option.
    public let choicesHidden: Bool
    public let listed: [Voter]
    /// Counted but not listed; only knowable once every page is in, so 0 until then.
    public let unlisted: Int
    /// The viewer's own Anonymous Ballot is among the unlisted.
    public let includesMine: Bool

    /// `votes` is the option's count and `participants` the Poll's Turnout, the total a list of everyone falls
    /// short of. `myAnonymousOptionId` is the viewer's option when their own Ballot is anonymous.
    public init(
        voters: [Voter], optionId: String, votes: Int, participants: Int, complete: Bool, myAnonymousOptionId: String?
    ) {
        let hidden = voters.contains { $0.optionId == nil }
        choicesHidden = hidden
        listed = hidden ? voters : voters.filter { $0.optionId == optionId }
        unlisted = complete ? max(0, (hidden ? participants : votes) - listed.count) : 0
        includesMine = myAnonymousOptionId.map { hidden || $0 == optionId } ?? false
    }
}

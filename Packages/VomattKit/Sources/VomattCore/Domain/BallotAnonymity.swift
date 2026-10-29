import Foundation

/// Whether the viewer's Ballot is left out of the voter list (the web's `useBallot`). A choice made
/// before the first vote rides along with it; until then it follows the account default.
public struct BallotAnonymity: Equatable, Sendable {
    /// The cast Ballot's flag; nil without a Ballot, or while it is not known.
    public var ballot: Bool?
    /// Chosen before voting; nil follows the account default.
    public private(set) var draft: Bool?

    public init(ballot: Bool?) {
        self.ballot = ballot
    }

    /// What the switch shows: a Ballot's own flag, or before one the choice so far.
    public func shown(hasBallot: Bool, accountDefault: Bool?) -> Bool? {
        hasBallot ? ballot : (draft ?? accountDefault ?? false)
    }

    /// What a first vote sends; nil leaves it to the API.
    public func forFirstVote(accountDefault: Bool?) -> Bool? {
        draft ?? accountDefault
    }

    /// Notes a choice made before voting.
    public mutating func choose(_ value: Bool) {
        draft = value
    }

    /// A first vote was saved with `flag`. A vote after withdrawing starts from the account default again.
    public mutating func voted(_ flag: Bool?) {
        ballot = flag
        draft = nil
    }
}

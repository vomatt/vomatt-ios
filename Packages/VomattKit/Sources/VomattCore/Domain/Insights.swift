import Foundation

public enum BallotOutcome: String, Sendable {
    case pending, won, tied, lost, unknown
}

public struct BallotRecord: Identifiable, Hashable, Sendable {
    public var id: String { poll.id }
    public var poll: Poll
    public var choice: String
    public var outcome: BallotOutcome
}

public struct Insights: Equatable, Sendable {
    /// People who voted on the user's polls.
    public var peopleReached: Int
    /// Share of decided Ballots where the pick won or tied, 0–100; nil before any are decided.
    public var majorityRate: Int?
    public var awaitingResults: Int
}

public enum AccountInsights {
    /// Whether the viewer's pick won an Ended Poll; `pending` while it is still open.
    public static func outcome(of poll: Poll, optionId: String, at now: Date = .now) -> BallotOutcome {
        guard poll.status(at: now) == .ended else { return .pending }
        guard let rows = poll.inlineResults else { return .unknown }
        let winners = Results.winners(rows)
        guard winners.contains(where: { $0.id == optionId }) else { return .lost }
        return winners.count > 1 ? .tied : .won
    }

    /// The viewer's Ballots among `polls`, in their order.
    public static func history(_ polls: [Poll], at now: Date = .now) -> [BallotRecord] {
        polls.compactMap { poll in
            guard let optionId = poll.myOptionId else { return nil }
            return BallotRecord(
                poll: poll,
                choice: poll.options.first { $0.id == optionId }?.text ?? "",
                outcome: outcome(of: poll, optionId: optionId, at: now)
            )
        }
    }

    public static func compute(myPolls: [Poll], history: [BallotRecord]) -> Insights {
        let decided = history.filter { $0.outcome != .pending && $0.outcome != .unknown }
        let withMajority = decided.filter { $0.outcome != .lost }.count
        let rate = decided.isEmpty ? nil : Int((Double(withMajority) / Double(decided.count) * 100).rounded())
        return Insights(
            peopleReached: myPolls.reduce(0) { $0 + ($1.turnout ?? 0) },
            majorityRate: rate,
            awaitingResults: history.filter { $0.outcome == .pending }.count
        )
    }
}

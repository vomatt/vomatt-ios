import Foundation

public enum BallotOutcome: String, Sendable {
    case pending, won, tied, lost, unknown
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

    /// The text of the option the viewer picked; empty when it is gone.
    public static func choice(of poll: Poll) -> String {
        poll.options.first { $0.id == poll.myOptionId }?.text ?? ""
    }
}

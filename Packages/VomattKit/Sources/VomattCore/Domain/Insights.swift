import Foundation

public enum BallotOutcome: String, Sendable {
    case pending, won, tied, lost, unknown
}

public enum AccountInsights {
    /// Whether the viewer's pick won an Ended Poll; `pending` while it is still open.
    public static func outcome(of poll: Poll, optionId: String, at now: Date = .now) -> BallotOutcome {
        guard poll.status(at: now) == .ended else { return .pending }
        guard let rows = poll.inlineResults else { return .unknown }
        return Results.outcome(of: optionId, in: rows) ?? .lost
    }

    /// The text of the option the viewer picked; empty when it is gone.
    public static func choice(of poll: Poll) -> String {
        poll.options.first { $0.id == poll.myOptionId }?.text ?? ""
    }
}

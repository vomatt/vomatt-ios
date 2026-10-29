import Foundation

/// What an Ended Poll decided: one winner, a tie, or nothing to say (no votes, cancelled, counts hidden).
public enum EndedSummary: Equatable, Sendable {
    case won(String)
    case tie([String])
    case none
}

/// The owner's Asked and Voted lists, from My Polls (the web's `features/profiles/lists.ts`).
public enum ProfileLists {
    /// The owner's own Polls, most recently opened first.
    public static func asked(_ polls: [Poll], viewerId: String) -> [Poll] {
        polls.filter { $0.creatorId == viewerId }.sorted { $0.startTime > $1.startTime }
    }

    /// Polls the owner voted in but didn't ask; My Polls mixes both.
    public static func voted(_ polls: [Poll], viewerId: String) -> [Poll] {
        polls.filter { $0.creatorId != viewerId && $0.myOptionId != nil }
    }

    /// Asked: Scheduled and Open Polls first (what happens next), then Ended ones.
    public static func splitAsked(_ polls: [Poll], at now: Date = .now) -> (open: [Poll], ended: [Poll]) {
        splitEnded(polls, at: now)
    }

    /// Voted: Sealed Ballots waiting for results first, then decided ones.
    public static func splitVoted(_ polls: [Poll], at now: Date = .now) -> (sealed: [Poll], decided: [Poll]) {
        splitEnded(polls, at: now)
    }

    private static func splitEnded(_ polls: [Poll], at now: Date) -> ([Poll], [Poll]) {
        var notEnded: [Poll] = []
        var ended: [Poll] = []
        for poll in polls {
            if poll.status(at: now) == .ended { ended.append(poll) } else { notEnded.append(poll) }
        }
        return (notEnded, ended)
    }

    /// Share of decided Ballots whose pick won outright, 0–100; nil before any is decided. A tie isn't a win.
    public static func picksWonRate(_ polls: [Poll], at now: Date = .now) -> Int? {
        var decided = 0
        var won = 0
        for poll in polls {
            guard let optionId = poll.myOptionId, !poll.isCancelled else { continue }
            let outcome = AccountInsights.outcome(of: poll, optionId: optionId, at: now)
            if outcome == .pending || outcome == .unknown { continue }
            decided += 1
            if outcome == .won { won += 1 }
        }
        return decided == 0 ? nil : Int((Double(won) / Double(decided) * 100).rounded())
    }

    /// What an Ended Poll decided; `.none` when cancelled or its counts are withheld.
    public static func endedSummary(_ poll: Poll) -> EndedSummary {
        guard !poll.isCancelled, let rows = poll.inlineResults else { return .none }
        let winners = Results.winners(rows)
        if winners.count == 1 { return .won(winners[0].text) }
        if winners.count > 1 { return .tie(winners.map(\.text)) }
        return .none
    }
}

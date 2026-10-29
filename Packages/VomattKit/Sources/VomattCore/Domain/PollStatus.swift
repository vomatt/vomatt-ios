import Foundation

/// `closing` is a UI hint only (an Open Poll ending within a day). It is never sent to the API.
public enum PollStatus: String, Sendable {
    case scheduled, open, closing, ended
}

private let closingWindow: TimeInterval = 24 * 60 * 60

extension Poll {
    /// Ended wins over Scheduled, so an old cancelled Scheduled Poll reads as Ended.
    public func status(at now: Date = .now) -> PollStatus {
        Poll.status(active: active, votingActive: votingActive, startTime: startTime, endTime: endTime, at: now)
    }

    public static func status(
        active: Bool, votingActive: Bool, startTime: Date, endTime: Date?, at now: Date = .now
    ) -> PollStatus {
        if !active || (endTime.map { $0 <= now } ?? false) { return .ended }
        if startTime > now { return .scheduled }
        if !votingActive { return .ended }
        if let endTime, endTime.timeIntervalSince(now) < closingWindow { return .closing }
        return .open
    }

    /// Closed before it opened, so it never took a Ballot or sent a notification.
    public var isCancelled: Bool {
        guard let endTime else { return false }
        return endTime <= startTime
    }

    public var visibilityLevel: VisibilityLevel? {
        guard let voterVisibility else { return nil }
        switch voterVisibility {
        case .nobody: return .nobody
        case .owner: return .owner
        case .signedIn: return audience == .inviteOnly ? .invited : .signedIn
        }
    }

    /// Only the owner and its Invitees can see an Invite-only Poll, so any other viewer is an Invitee.
    public func isInvitee(viewerId: String) -> Bool {
        audience == .inviteOnly && creatorId != viewerId
    }

    /// Ended before its Deadline: Closed by the owner, or every Invitee voted.
    public var endedEarly: Bool {
        guard let endTime, let deadline else { return false }
        return endTime < deadline
    }

    /// Turnout: how many people hold a Ballot. Visible in every state.
    public var turnout: Int? { participantCount }

    /// How far through its voting window the Poll is, 0–100.
    public func timelineProgress(at now: Date = .now) -> Double? {
        guard let endTime else { return nil }
        let span = endTime.timeIntervalSince(startTime)
        if span <= 0 { return 100 }
        return min(100, max(0, now.timeIntervalSince(startTime) / span * 100))
    }

    /// Counts are in the Poll itself once Ended; otherwise nil (fetch `/results`).
    public var inlineResults: [ResultRow]? {
        if options.contains(where: { $0.votes == nil }) { return nil }
        return options.map { ResultRow(id: $0.id, text: $0.text, votes: $0.votes ?? 0) }
    }

    /// Whether the viewer may see who chose what once it has Ended.
    /// Whether hiding the viewer's name means anything: nobody sees a "nobody" Poll's voter list.
    public var allowsAnonymousBallot: Bool { voterVisibility != .nobody }

    public func canSeeVoters(viewerId: String?) -> Bool {
        switch voterVisibility {
        case .signedIn: return viewerId != nil
        case .owner: return viewerId != nil && viewerId == creatorId
        default: return false
        }
    }

    /// Edit while Scheduled; Delete while Scheduled or `deletable`; End now for an Open
    /// Unlisted or Invite-only Poll; Invitees until an Invite-only Poll Ends.
    public func ownerActions(at now: Date = .now) -> OwnerActions {
        let status = status(at: now)
        let canEnd = (status == .open || status == .closing) && (audience == .unlisted || audience == .inviteOnly)
        return OwnerActions(
            canEdit: status == .scheduled,
            canDelete: status == .scheduled || deletable == true,
            canEnd: canEnd,
            canInvite: audience == .inviteOnly && status != .ended
        )
    }
}

public struct OwnerActions: Equatable, Sendable {
    public var canEdit: Bool
    public var canDelete: Bool
    public var canEnd: Bool
    public var canInvite: Bool
    public var any: Bool { canEdit || canDelete || canEnd || canInvite }
}

public struct ResultRow: Identifiable, Hashable, Sendable {
    public let id: String
    public var text: String
    public var votes: Int

    public init(id: String, text: String, votes: Int) {
        self.id = id
        self.text = text
        self.votes = votes
    }
}

public enum Results {
    /// The rows with the most votes; none when nobody voted.
    public static func winners(_ rows: [ResultRow]) -> [ResultRow] {
        let top = rows.map(\.votes).max() ?? 0
        return top > 0 ? rows.filter { $0.votes == top } : []
    }

    /// What the rows decided: one winner, a tie, or no votes.
    public static func summary(_ rows: [ResultRow]) -> EndedSummary {
        let winners = winners(rows)
        if winners.count == 1 { return .won(winners[0].text) }
        if winners.count > 1 { return .tie(winners.map(\.text)) }
        return .none
    }

    /// How the viewer's pick fared: won, tied for first or outvoted; nil without a pick among the rows.
    public static func outcome(of optionId: String?, in rows: [ResultRow]) -> BallotOutcome? {
        guard let optionId, rows.contains(where: { $0.id == optionId }) else { return nil }
        let winners = winners(rows)
        guard winners.contains(where: { $0.id == optionId }) else { return .lost }
        return winners.count > 1 ? .tied : .won
    }

    /// Share of Participants, rounded to a whole percent.
    public static func support(votes: Int, participants: Int) -> Int {
        participants == 0 ? 0 : Int((Double(votes) / Double(participants) * 100).rounded())
    }
}

/// Moves an optimistic count, never below 0; an unknown count stays unknown.
public func shiftCount(_ count: Int?, by delta: Int) -> Int? {
    count.map { max(0, $0 + delta) }
}

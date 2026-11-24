import Foundation

/// The API Ends an Invite-only Poll as soon as every Invitee (at least one) holds a Ballot (the web's `everyInviteeVoted`).
public func everyInviteeVoted(_ invitees: [Invitee]) -> Bool {
    !invitees.isEmpty && invitees.allSatisfy(\.hasBallot)
}

extension Invitee {
    /// Whether removing this Invitee from `invitees` Ends the Poll: everyone left has voted.
    public func removalEndsPoll(in invitees: [Invitee]) -> Bool {
        everyInviteeVoted(invitees.filter { $0.id != id })
    }
}

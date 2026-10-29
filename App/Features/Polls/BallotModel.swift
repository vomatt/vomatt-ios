import Observation
import SwiftUI
import VomattCore

/// The viewer's Ballot on one Poll (the web's `useBallot`): their choice, the option
/// selected but not yet cast, and an optimistic Turnout.
@Observable
final class BallotModel {
    enum Outcome { case saved, failed, ended }
    /// What a request in flight is doing: a first vote, a changed vote, a withdrawal or the anonymity switch.
    enum Action { case vote, update, retract, anonymous }

    private(set) var pollId: String
    private(set) var myOptionId: String?
    var selected: String?
    private var anonymity: BallotAnonymity
    private(set) var turnout: Int?
    private(set) var pendingAction: Action?
    var isPending: Bool { pendingAction != nil }

    init(poll: Poll) {
        pollId = poll.id
        myOptionId = poll.myOptionId
        selected = poll.myOptionId
        anonymity = BallotAnonymity(ballot: poll.myBallotAnonymous)
        turnout = poll.turnout
    }

    /// Whether the Ballot, or the vote about to be cast, is left out of the voter list. A withdrawal in
    /// flight keeps the Ballot's flag.
    func anonymous(accountDefault: Bool?) -> Bool? {
        anonymity.shown(hasBallot: myOptionId != nil || pendingAction == .retract, accountDefault: accountDefault)
    }

    /// A refetched Poll carries fresh counts and the viewer's Ballot.
    func sync(_ poll: Poll) {
        guard !isPending else { return }
        // Keep an option the voter selected but hasn't submitted unless the Ballot itself changed
        let ballotChanged = poll.myOptionId != myOptionId
        pollId = poll.id
        myOptionId = poll.myOptionId
        if selected == nil || (ballotChanged && poll.myOptionId != nil) { selected = poll.myOptionId }
        anonymity.ballot = poll.myBallotAnonymous
        turnout = poll.turnout
    }

    /// Casts a first Ballot, with the anonymity chosen so far, or replaces the current one.
    func cast(_ optionId: String, app: AppModel, onPollChanged: (Poll) -> Void, onPollEnded: () async -> Void) async -> Outcome {
        if myOptionId != nil {
            return await send(.update, optionId, anonymous: nil, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
        }
        let chosen = anonymity.forFirstVote(accountDefault: app.me?.anonymousBallotByDefault)
        let outcome = await send(.vote, optionId, anonymous: chosen, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
        if outcome == .saved { anonymity.voted(anonymity.ballot) }
        return outcome
    }

    /// Recasts the current option to add the Ballot to, or drop it from, the voter list; before a vote,
    /// only notes the choice.
    func setAnonymous(_ value: Bool, app: AppModel, onPollChanged: (Poll) -> Void, onPollEnded: () async -> Void) async -> Outcome {
        guard let optionId = myOptionId else {
            anonymity.choose(value)
            return .saved
        }
        return await send(.anonymous, optionId, anonymous: value, app: app, onPollChanged: onPollChanged, onPollEnded: onPollEnded)
    }

    private func send(
        _ action: Action, _ optionId: String, anonymous: Bool?, app: AppModel,
        onPollChanged: (Poll) -> Void, onPollEnded: () async -> Void
    ) async -> Outcome {
        // The switch shows the new flag while the request is out
        let shownAnonymous = action == .update ? nil : (anonymous ?? false)
        return await run(action, next: optionId, nextAnonymous: shownAnonymous, failure: "poll.voteFailed",
                         app: app, onPollEnded: onPollEnded) {
            let poll = try await app.service.castBallot(pollId: pollId, optionId: optionId, anonymous: anonymous)
            self.anonymity.ballot = poll.myBallotAnonymous
            onPollChanged(poll)
        }
    }

    /// Withdraws the current Ballot.
    func retract(app: AppModel, onPollEnded: () async -> Void) async -> Outcome {
        // Nothing to withdraw is already the desired state, not a failure
        guard myOptionId != nil else { return .saved }
        return await run(.retract, next: nil, failure: "poll.withdrawFailed", app: app, onPollEnded: onPollEnded) {
            try await app.service.retractBallot(pollId: pollId)
        }
    }

    private func run(
        _ action: Action, next: String?, nextAnonymous: Bool? = nil, failure: String, app: AppModel, onPollEnded: () async -> Void,
        request: () async throws -> Void
    ) async -> Outcome {
        let previous = myOptionId
        let previousAnonymous = anonymity.ballot
        let delta = (next == nil ? 0 : 1) - (previous == nil ? 0 : 1)
        // An anonymity recast keeps an option the voter selected but hasn't submitted
        let keepsSelection = action == .anonymous
        pendingAction = action
        myOptionId = next
        if !keepsSelection { selected = next }
        if let nextAnonymous { anonymity.ballot = nextAnonymous }
        turnout = shiftCount(turnout, by: delta)
        do {
            try await request()
            pendingAction = nil
            return .saved
        } catch {
            pendingAction = nil
            myOptionId = previous
            if !keepsSelection { selected = previous }
            anonymity.ballot = previousAnonymous
            turnout = shiftCount(turnout, by: -delta)
            let apiError = error as? APIError
            if apiError?.isPollEnded == true {
                app.showToast(app.t("poll.justEnded"))
                await onPollEnded()
                return .ended
            }
            if apiError?.kind == .notAuthenticated {
                app.signIn()
                return .failed
            }
            // Still busy after the service's retry: common.conflict shows common.busy
            let busyMessage = apiError?.isBusy == true ? app.t.message(for: error, fallback: failure) : nil
            app.showToast(busyMessage ?? app.t(apiError?.isRateLimited == true ? "poll.tooManyVotes" : failure), isError: true)
            return .failed
        }
    }
}

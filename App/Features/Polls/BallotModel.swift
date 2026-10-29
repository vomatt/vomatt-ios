import Observation
import SwiftUI
import VomattCore

/// The viewer's Ballot on one Poll (the web's `useBallot`): their choice, the option
/// selected but not yet cast, and an optimistic Turnout.
@Observable
final class BallotModel {
    enum Outcome { case saved, failed, ended }

    private(set) var pollId: String
    private(set) var myOptionId: String?
    var selected: String?
    /// nil while there is no Ballot, or while it is not known whether it is Anonymous.
    private(set) var anonymous: Bool?
    private(set) var turnout: Int?
    private(set) var isPending = false

    init(poll: Poll) {
        pollId = poll.id
        myOptionId = poll.myOptionId
        selected = poll.myOptionId
        anonymous = poll.myBallotAnonymous
        turnout = poll.turnout
    }

    /// A refetched Poll carries fresh counts and the viewer's Ballot.
    func sync(_ poll: Poll) {
        guard !isPending else { return }
        // Keep an option the voter selected but hasn't submitted unless the Ballot itself changed
        let ballotChanged = poll.myOptionId != myOptionId
        pollId = poll.id
        myOptionId = poll.myOptionId
        if selected == nil || (ballotChanged && poll.myOptionId != nil) { selected = poll.myOptionId }
        anonymous = poll.myBallotAnonymous
        turnout = poll.turnout
    }

    /// Casts a first Ballot or replaces the current one. Recasting the current option with
    /// `anonymous` adds the Ballot to, or drops it from, the voter list.
    func cast(
        _ optionId: String, anonymous: Bool? = nil, app: AppModel,
        onPollChanged: (Poll) -> Void, onPollEnded: () async -> Void
    ) async -> Outcome {
        await run(next: optionId, nextAnonymous: anonymous, failure: "poll.voteFailed", app: app, onPollEnded: onPollEnded) {
            let poll = try await app.service.castBallot(pollId: pollId, optionId: optionId, anonymous: anonymous)
            self.anonymous = poll.myBallotAnonymous
            onPollChanged(poll)
        }
    }

    /// Withdraws the current Ballot.
    func retract(app: AppModel, onPollEnded: () async -> Void) async -> Outcome {
        // Nothing to withdraw is already the desired state, not a failure
        guard myOptionId != nil else { return .saved }
        return await run(next: nil, failure: "poll.withdrawFailed", app: app, onPollEnded: onPollEnded) {
            try await app.service.retractBallot(pollId: pollId)
        }
    }

    private func run(
        next: String?, nextAnonymous: Bool? = nil, failure: String, app: AppModel, onPollEnded: () async -> Void,
        request: () async throws -> Void
    ) async -> Outcome {
        let previous = myOptionId
        let previousAnonymous = anonymous
        let delta = (next == nil ? 0 : 1) - (previous == nil ? 0 : 1)
        // An anonymity recast keeps an option the voter selected but hasn't submitted
        let keepsSelection = nextAnonymous != nil
        isPending = true
        myOptionId = next
        if !keepsSelection { selected = next }
        if let nextAnonymous { anonymous = nextAnonymous }
        turnout = shiftCount(turnout, by: delta)
        do {
            try await request()
            isPending = false
            return .saved
        } catch {
            isPending = false
            myOptionId = previous
            if !keepsSelection { selected = previous }
            anonymous = previousAnonymous
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

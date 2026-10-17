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
    private(set) var turnout: Int?
    private(set) var isPending = false

    init(poll: Poll) {
        pollId = poll.id
        myOptionId = poll.myOptionId
        selected = poll.myOptionId
        turnout = poll.turnout
    }

    /// A refetched Poll carries fresh counts and the viewer's Ballot.
    func sync(_ poll: Poll) {
        guard !isPending else { return }
        pollId = poll.id
        myOptionId = poll.myOptionId
        if selected == nil || poll.myOptionId != nil { selected = poll.myOptionId }
        turnout = poll.turnout
    }

    /// Casts a first Ballot or replaces the current one.
    func cast(_ optionId: String, app: AppModel, onPollChanged: (Poll) -> Void, onPollEnded: () async -> Void) async -> Outcome {
        await run(next: optionId, failure: "poll.voteFailed", app: app, onPollEnded: onPollEnded) {
            let poll = try await app.service.castBallot(pollId: pollId, optionId: optionId)
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
        next: String?, failure: String, app: AppModel, onPollEnded: () async -> Void,
        request: () async throws -> Void
    ) async -> Outcome {
        let previous = myOptionId
        let delta = (next == nil ? 0 : 1) - (previous == nil ? 0 : 1)
        isPending = true
        myOptionId = next
        selected = next
        turnout = shiftCount(turnout, by: delta)
        do {
            try await request()
            isPending = false
            return .saved
        } catch {
            isPending = false
            myOptionId = previous
            selected = previous
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
            app.showToast(app.t(apiError?.isRateLimited == true ? "poll.tooManyVotes" : failure), isError: true)
            return .failed
        }
    }
}

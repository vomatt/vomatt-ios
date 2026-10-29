import Foundation

/// The poll page's list of the author's other Polls (the web's `MoreFromAuthor`).
public enum MoreFromAuthor {
    /// Two of the author's Polls other than this one.
    public static func pick(_ polls: [Poll], excluding pollId: String) -> [Poll] {
        Array(polls.filter { $0.id != pollId }.prefix(2))
    }

    /// "ended · 611 voted", "ends in 2h · 96 voted".
    public static func meta(_ poll: Poll, now: Date = .now, t: Localizer, dates: DateFormatting) -> String {
        let turnout = t("poll.voted", ["count": t.number(poll.turnout ?? 0)])
        let status = poll.status(at: now)
        let when = status == .ended
            ? t("pollDetail.ended")
            : PollTiming(startTime: poll.startTime, endTime: poll.endTime, status: status, now: now, t: t, dates: dates).when
        return when.map { "\($0) · \(turnout)" } ?? turnout
    }
}

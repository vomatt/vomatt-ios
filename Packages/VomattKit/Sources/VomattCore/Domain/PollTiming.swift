import Foundation

/// Every way a poll surface says when, from the web's `features/polls/timing.ts`. Derived; never stored.
public struct PollTiming: Equatable, Sendable {
    /// A chip that stands alone: "Opens Mon 9:00", "Ends Fri 20:00", "Ends in 6h", "Ended Mon".
    public let chip: String
    /// The time for a meta line beside a status-word chip: "ends Fri 20:00", "ends in 6h"; a Scheduled
    /// poll's "Opens Mon 9:00" stands alone. Nil once ended and for an Open poll without an end.
    public let when: String?

    public init(chip: String, when: String?) {
        self.chip = chip
        self.when = when
    }

    public init(startTime: Date, endTime: Date?, status: PollStatus, now: Date = .now, t: Localizer, dates: DateFormatting) {
        switch status {
        case .scheduled:
            let opens = t("poll.chipOpens", ["date": dates.pollMoment(startTime, now: now)])
            self.init(chip: opens, when: opens)
        case .ended:
            let chip = endTime.map { t("poll.chipEnded", ["day": dates.pollDay($0, now: now)]) } ?? Self.statusWord(.ended, t)
            self.init(chip: chip, when: nil)
        case .closing, .open:
            guard let endTime else {
                self.init(chip: Self.statusWord(.open, t), when: nil)
                return
            }
            if status == .closing {
                let duration = dates.duration(endTime.timeIntervalSince(now))
                self.init(chip: t("poll.chipEndsIn", ["duration": duration]), when: t("poll.endsIn", ["duration": duration]))
            } else {
                let date = dates.pollMoment(endTime, now: now)
                self.init(chip: t("poll.chipEnds", ["date": date]), when: t("profile.endsAt", ["date": date]))
            }
        }
    }

    /// The chip's word for a status: Soon / Open / Closing / Ended.
    public static func statusWord(_ status: PollStatus, _ t: Localizer) -> String {
        t("poll.status.\(status.rawValue)")
    }
}

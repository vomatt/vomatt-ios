import Foundation

/// Which day a notification falls on, in the reader's calendar, from the web's `dayGroup`.
public enum ActivityDay: String, CaseIterable, Sendable {
    case today, yesterday, earlier

    public init(_ date: Date, now: Date, calendar: Calendar) {
        let startOfToday = calendar.startOfDay(for: now)
        if date >= startOfToday {
            self = .today
        } else if let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday), date >= startOfYesterday {
            self = .yesterday
        } else {
            self = .earlier
        }
    }
}

/// What the Activity list shows as one row: a notification, or a run of follows folded into one
/// ("@bkim and 2 others followed you"), from the web's `groupFollows`.
public enum ActivityEntry: Identifiable, Hashable, Sendable {
    case single(FeedNotification)
    /// Two or more consecutive follows, newest first.
    case follows([FeedNotification])

    public var id: String { items[0].id }

    /// The notifications the entry stands for, which opening it reads.
    public var items: [FeedNotification] {
        switch self {
        case let .single(item): [item]
        case let .follows(items): items
        }
    }

    public var isUnread: Bool { items.contains { !$0.read } }

    /// Folds each run of two or more consecutive follows into one entry.
    public static func entries(_ items: [FeedNotification]) -> [ActivityEntry] {
        var entries: [ActivityEntry] = []
        var run: [FeedNotification] = []
        func flush() {
            if run.count > 1 { entries.append(.follows(run)) } else { entries += run.map(ActivityEntry.single) }
            run = []
        }
        for item in items {
            if item.kind == .followed { run.append(item); continue }
            flush()
            entries.append(.single(item))
        }
        flush()
        return entries
    }
}

/// One day's heading and its rows, in the feed's order (newest first).
public struct ActivitySection: Identifiable, Hashable, Sendable {
    public let day: ActivityDay
    public let entries: [ActivityEntry]
    public var id: ActivityDay { day }

    /// Today, Yesterday, Earlier; days with nothing are left out.
    public static func sections(_ items: [FeedNotification], now: Date = .now, calendar: Calendar = .current) -> [ActivitySection] {
        ActivityDay.allCases.compactMap { day in
            let entries = ActivityEntry.entries(items.filter { ActivityDay($0.createdAt, now: now, calendar: calendar) == day })
            return entries.isEmpty ? nil : ActivitySection(day: day, entries: entries)
        }
    }
}

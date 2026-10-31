import CoreGraphics
import Foundation

/// Which notifications to mark read and when, from the web's `useMarkRead`. Opening a row reads it at
/// once; a row that was seen waits in a queue so rows seen close together are read in one batch, with
/// one recount of the badge. Each id is sent once; ids the server leaves unread go back in the queue.
public struct NotificationReads: Sendable {
    /// Ids queued within this long of each other are read together (`READ_BATCH_MS`).
    public static let batchDelay: TimeInterval = 2
    /// The longest an id waits while more keep arriving (`READ_MAX_WAIT_MS`).
    public static let maxWait: TimeInterval = 5
    /// How long a row stays at least half on screen before it counts as read (`SEEN_MS`).
    public static let seenDelay: Duration = .seconds(1)
    /// How much of a row must be on screen to count as seen.
    public static let seenFraction = 0.5

    private var sent: Set<String> = []
    private var queued: [String] = []
    private var batchDeadline: Date?
    private var maxDeadline: Date?

    public init() {}

    /// When the queue should be sent; nil while nothing waits for a batch.
    public var deadline: Date? {
        [batchDeadline, maxDeadline].compactMap { $0 }.min()
    }

    /// The ids to send now because the person opened them: those not sent already.
    public mutating func read(_ ids: [String]) -> [String] {
        var unsent: [String] = []
        for id in ids where !sent.contains(id) {
            sent.insert(id)
            unsent.append(id)
        }
        return unsent
    }

    /// Queues ids that were seen; each restarts the batch wait, within the longest wait of the first.
    public mutating func queue(_ ids: [String], at now: Date) {
        append(ids)
        batchDeadline = now.addingTimeInterval(Self.batchDelay)
        if maxDeadline == nil { maxDeadline = now.addingTimeInterval(Self.maxWait) }
    }

    /// Takes the queue to send: its deadline came, the app went to the background, or the list closed.
    public mutating func flush() -> [String] {
        batchDeadline = nil
        maxDeadline = nil
        let ids = queued
        queued = []
        return read(ids)
    }

    /// Ids the server left unread wait for whatever sends the queue next, without starting a wait of their own.
    public mutating func requeue(_ ids: [String]) {
        sent.subtract(ids)
        append(ids)
    }

    private mutating func append(_ ids: [String]) {
        for id in ids where !queued.contains(id) { queued.append(id) }
    }

    /// How much of `rect` lies inside `viewport`, 0 to 1, by area.
    public static func visibleFraction(of rect: CGRect, in viewport: CGRect) -> Double {
        let area = rect.width * rect.height
        guard area > 0 else { return 0 }
        let visible = rect.intersection(viewport)
        return visible.isNull ? 0 : Double(visible.width * visible.height / area)
    }
}

extension ActivityEntry {
    /// The ids of its items not read yet.
    public var unreadIds: [String] { items.filter { !$0.read }.map(\.id) }

    /// Whether seeing the row should read it: some unread item not seen this visit, and not a result,
    /// which stays until opened so a sealed promise is never lost in the list.
    public func readsWhenSeen(seen: Set<String>) -> Bool {
        items[0].kind != .result && unreadIds.contains { !seen.contains($0) }
    }
}

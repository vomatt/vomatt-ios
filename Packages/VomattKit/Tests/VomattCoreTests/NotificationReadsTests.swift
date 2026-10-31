import CoreGraphics
import Foundation
import Testing
@testable import VomattCore

/// Ported from the "NotificationList read state" cases of vomatt-web
/// `src/__tests__/features/notifications/NotificationList.test.tsx` (the `useMarkRead` and `useSeen` parts).
@Suite("Notification reads")
struct NotificationReadsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func anOpenedItemIsSentOnceAndNotAgain() {
        var reads = NotificationReads()
        #expect(reads.read(["invitation_p2"]) == ["invitation_p2"])
        #expect(reads.read(["invitation_p2"]).isEmpty)
    }

    @Test func rowsSeenTogetherAreSentInOneBatchAfterTheBatchWait() {
        var reads = NotificationReads()
        reads.queue(["invitation_p2"], at: at(0))
        reads.queue(["follow_bkim", "follow_jtan"], at: at(0.5))
        #expect(reads.deadline == at(0.5 + NotificationReads.batchDelay))
        #expect(reads.flush() == ["invitation_p2", "follow_bkim", "follow_jtan"])
        #expect(reads.deadline == nil)
    }

    @Test func aSeenRowOpenedLaterIsNotSentAgain() {
        var reads = NotificationReads()
        reads.queue(["invitation_p2"], at: at(0))
        _ = reads.flush()
        #expect(reads.read(["invitation_p2"]).isEmpty)
    }

    @Test func aBatchGoesAfterTheLongestWaitWhileRowsKeepBeingSeen() {
        var reads = NotificationReads()
        // A row every 1.5s keeps restarting the 2s batch wait
        for n in 0..<4 { reads.queue(["comment_c\(n + 1)"], at: at(Double(n) * 1.5)) }
        #expect(reads.deadline == at(NotificationReads.maxWait))
        #expect(reads.flush() == ["comment_c1", "comment_c2", "comment_c3", "comment_c4"])
    }

    @Test func idsTheServerLeftUnreadGoWithTheNextBatch() {
        var reads = NotificationReads()
        reads.queue(["follow_bkim"], at: at(0))
        #expect(reads.flush() == ["follow_bkim"])
        reads.requeue(["follow_bkim"])
        // Requeued ids wait without starting a wait of their own
        #expect(reads.deadline == nil)
        reads.queue(["invitation_p2"], at: at(3))
        #expect(reads.flush() == ["follow_bkim", "invitation_p2"])
        reads.requeue(["follow_bkim", "invitation_p2"])
        reads.queue(["follow_jtan"], at: at(6))
        #expect(reads.flush() == ["follow_bkim", "invitation_p2", "follow_jtan"])
    }

    @Test func aRowCountsAsSeenOnlyWithAtLeastHalfOfItOnScreen() {
        let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)
        let row = { (y: CGFloat) in CGRect(x: 0, y: y, width: 400, height: 100) }
        #expect(NotificationReads.visibleFraction(of: row(100), in: viewport) == 1)
        #expect(NotificationReads.visibleFraction(of: row(750), in: viewport) == 0.5)
        #expect(NotificationReads.visibleFraction(of: row(780), in: viewport) < NotificationReads.seenFraction)
        #expect(NotificationReads.visibleFraction(of: row(900), in: viewport) == 0)
    }

    @Test func aResultStaysUnreadUntilOpenedAndAReadRowHasNothingToWatch() {
        let ended = FeedNotification(id: "result_p1", kind: .result, createdAt: start, poll: .init(id: "p1", title: "T", isEnded: true))
        let invite = FeedNotification(id: "invitation_p2", kind: .invitation, createdAt: start, poll: .init(id: "p2", title: "T"))
        var read = invite
        read.read = true
        #expect(!ActivityEntry.single(ended).readsWhenSeen(seen: []))
        #expect(ActivityEntry.single(invite).readsWhenSeen(seen: []))
        #expect(!ActivityEntry.single(invite).readsWhenSeen(seen: ["invitation_p2"]))
        #expect(!ActivityEntry.single(read).readsWhenSeen(seen: []))
    }

    @Test func aGroupOfFollowsReadsEveryUnreadFollow() {
        let follows = ["bkim", "jtan"].map {
            FeedNotification(id: "follow_\($0)", kind: .followed, createdAt: start, actor: UserSummary(id: $0, username: $0))
        }
        let entry = ActivityEntry.follows(follows)
        #expect(entry.unreadIds == ["follow_bkim", "follow_jtan"])
        #expect(entry.readsWhenSeen(seen: ["follow_bkim"]))
    }
}

import Foundation
import Testing
@testable import VomattCore

private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func comment(_ id: String, minute: Double = 0, parentId: String? = nil,
                     replies: [VomattCore.Comment] = []) -> VomattCore.Comment {
    VomattCore.Comment(id: id, author: "alice", text: id, createdAt: base.addingTimeInterval(minute * 60),
                       parentId: parentId, replyCount: replies.count, replies: replies)
}

private func page(_ items: [VomattCore.Comment], _ nextCursor: String?) -> CursorPage<VomattCore.Comment> {
    CursorPage(items: items, nextCursor: nextCursor)
}

private func ids(_ items: [VomattCore.Comment]) -> [String] { items.map(\.id) }

@Suite("Comment thread refresh")
struct CommentThreadTests {
    @Test func keepsCommentsFromLaterPagesWithTheCursorAfterThem() {
        var thread = CommentThread(comments: [comment("c1"), comment("c2"), comment("c3")],
                                   nextCursor: "cursor-3", hasLaterPages: true)
        let kept = thread.applyFirstPage(page([comment("c0"), comment("c1")], "cursor-fresh"), keepLoaded: true, postedHere: [])
        #expect(kept)
        #expect(ids(thread.comments) == ["c0", "c1", "c2", "c3"])
        #expect(thread.nextCursor == "cursor-3")
    }

    @Test func refreshOfTheFirstPageOnlyTakesTheNewCursor() {
        var thread = CommentThread(comments: [comment("c1"), comment("c2")], nextCursor: "cursor-2")
        thread.applyFirstPage(page([comment("c0"), comment("c1")], "cursor-fresh"), keepLoaded: true, postedHere: [])
        #expect(ids(thread.comments) == ["c0", "c1", "c2"])
        #expect(thread.nextCursor == "cursor-fresh")
    }

    @Test func startsOverWhenThePageReachesNoneOfTheCommentsShown() {
        var thread = CommentThread(comments: [comment("c1"), comment("c2"), comment("c3")],
                                   nextCursor: "cursor-3", hasLaterPages: true)
        let kept = thread.applyFirstPage(page([comment("n1"), comment("n2")], "cursor-n"), keepLoaded: true, postedHere: [])
        #expect(!kept)
        #expect(ids(thread.comments) == ["n1", "n2"])
        #expect(thread.nextCursor == "cursor-n")
        #expect(!thread.hasLaterPages)
    }

    @Test func dropsACommentThePageSkipsAsDeletedElsewhere() {
        var thread = CommentThread(comments: [comment("c3", minute: 3), comment("c2", minute: 2), comment("c1", minute: 1)])
        thread.applyFirstPage(page([comment("c3", minute: 3), comment("c1", minute: 1)], nil), keepLoaded: true, postedHere: [])
        #expect(ids(thread.comments) == ["c3", "c1"])
    }

    @Test func keepsACommentStillPostingOrPostedHereOnTop() {
        var thread = CommentThread(comments: [comment("pending-1", minute: 5), comment("saved", minute: 4), comment("c1")])
        thread.applyFirstPage(page([comment("c1")], nil), keepLoaded: true, postedHere: ["saved"])
        #expect(ids(thread.comments) == ["pending-1", "saved", "c1"])
    }

    @Test func anOlderCommentPostedHereStaysInItsPlace() {
        var thread = CommentThread(comments: [comment("c2", minute: 2), comment("mine", minute: 1)])
        thread.applyFirstPage(page([comment("c3", minute: 3), comment("c2", minute: 2)], "cursor"), keepLoaded: true,
                              postedHere: ["mine"])
        #expect(ids(thread.comments) == ["c3", "c2", "mine"])
    }

    @Test func aCompleteFirstPageDropsAnOlderCommentItNoLongerLists() {
        var thread = CommentThread(comments: [comment("c3", minute: 3), comment("c2", minute: 2), comment("c1", minute: 1)])
        thread.applyFirstPage(page([comment("c3", minute: 3), comment("c2", minute: 2)], nil), keepLoaded: true, postedHere: [])
        #expect(ids(thread.comments) == ["c3", "c2"])
    }

    @Test func aPostedCommentThePageListsComesFromThePage() {
        var thread = CommentThread(comments: [comment("saved", minute: 4), comment("c1")])
        thread.applyFirstPage(page([comment("saved", minute: 4), comment("c1")], nil), keepLoaded: true, postedHere: ["saved"])
        #expect(ids(thread.comments) == ["saved", "c1"])
    }

    @Test func keepsRepliesLoadedPastThePreview() {
        let r = (1...3).map { comment("r\($0)", minute: Double($0), parentId: "c1") }
        var thread = CommentThread(comments: [comment("c1", replies: Array(r.prefix(2)))],
                                   replies: ["c1": ReplyList(items: r, nextCursor: nil)])
        var fresh = comment("c1", replies: Array(r.prefix(2)))
        fresh.repliesNextCursor = "after-r2"
        thread.applyFirstPage(page([fresh], nil), keepLoaded: true, postedHere: [])
        #expect(ids(thread.replies["c1"]?.items ?? []) == ["r1", "r2", "r3"])
        #expect(thread.replies["c1"]?.nextCursor == nil)
    }

    @Test func dropsAReplyThePreviewNoLongerLists() {
        let r = (1...2).map { comment("r\($0)", minute: Double($0), parentId: "c1") }
        var thread = CommentThread(comments: [comment("c1", replies: r)], replies: ["c1": ReplyList(items: r)])
        thread.applyFirstPage(page([comment("c1", replies: [r[1]])], nil), keepLoaded: true, postedHere: [])
        #expect(ids(thread.replies["c1"]?.items ?? []) == ["r2"])
    }

    @Test func dropsTheRepliesOfACommentNoLongerShown() {
        let r1 = comment("r1", parentId: "c2")
        var thread = CommentThread(comments: [comment("c1", minute: 1), comment("c2", minute: 2, replies: [r1])],
                                   replies: ["c2": ReplyList(items: [r1])])
        thread.applyFirstPage(page([comment("c3", minute: 3), comment("c1", minute: 1)], nil), keepLoaded: true, postedHere: [])
        #expect(thread.replies["c2"] == nil)
    }

    @Test func keepsAReplyStillPostingUnderACommentTheRefreshBringsAgain() {
        let r1 = comment("r1", parentId: "c1")
        var thread = CommentThread(comments: [comment("c1", replies: [r1])],
                                   replies: ["c1": ReplyList(items: [r1, comment("pending-r", minute: 60, parentId: "c1")])])
        thread.applyFirstPage(page([comment("c1", replies: [r1])], nil), keepLoaded: true, postedHere: [])
        #expect(ids(thread.replies["c1"]?.items ?? []) == ["r1", "pending-r"])
    }

    @Test func keepsAReplyStillPostingWhenTheRefreshStartsOver() {
        var thread = CommentThread(comments: [comment("c1")],
                                   replies: ["c1": ReplyList(items: [comment("pending-r", parentId: "c1")])])
        thread.applyFirstPage(page([comment("n1"), comment("n2")], "cursor-n"), keepLoaded: true, postedHere: [])
        #expect(ids(thread.replies["c1"]?.items ?? []) == ["pending-r"])
    }

    @Test func aFirstLoadKeepsOnlyWhatIsPosting() {
        var thread = CommentThread(comments: [comment("c1")],
                                   replies: ["c1": ReplyList(items: [comment("r1", parentId: "c1")])])
        let kept = thread.applyFirstPage(page([comment("c1")], nil), keepLoaded: false, postedHere: [])
        #expect(!kept)
        #expect(thread.replies.isEmpty)
    }

    @Test func countsCommentsAndRepliesStillPosting() {
        let thread = CommentThread(comments: [comment("pending-1"), comment("c1")],
                                   replies: ["c1": ReplyList(items: [comment("r1", parentId: "c1"), comment("pending-2", parentId: "c1")])])
        #expect(thread.postingCount == 2)
        #expect(shiftCount(2, by: thread.postingCount) == 4)
    }
}

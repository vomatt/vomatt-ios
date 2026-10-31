import Foundation
import Testing
@testable import VomattCore

private func comment(_ text: String?, parentId: String? = "c1") -> VomattCore.Comment {
    VomattCore.Comment(id: "r1", author: "june", text: text, createdAt: .now, parentId: parentId)
}

@Suite("Comment mentions")
struct CommentMentionTests {
    @Test func replyPrefixBecomesTheAddressee() {
        let reply = comment("@tom The 27 and the 31.")
        #expect(reply.addressee == "tom")
        #expect(reply.bodyText == "The 27 and the 31.")
    }

    @Test func prefixRoundTrips() {
        #expect(comment(VomattCore.Comment.replyPrefix(to: "tom") + "Which buses?").addressee == "tom")
    }

    @Test func topLevelCommentKeepsItsText() {
        let root = comment("@tom hi", parentId: nil)
        #expect(root.addressee == nil)
        #expect(root.bodyText == "@tom hi")
    }

    @Test func mentionAloneIsJustText() {
        #expect(comment("@tom").addressee == nil)
        #expect(comment("@tom   ").bodyText == "@tom   ")
    }

    @Test func noMentionNoAddressee() {
        #expect(comment("Fair point about parking though.").addressee == nil)
        #expect(comment(nil).bodyText == nil)
    }
}

@Suite("Comment mention links")
struct CommentMentionLinkTests {
    private func linked(_ text: String, _ names: String...) -> [VomattCore.Comment.Segment] {
        VomattCore.Comment(
            id: "c1", author: "june", text: text, createdAt: .now,
            mentions: names.map { .init(userId: "u-\($0)", username: $0) }
        ).bodySegments
    }

    @Test func linksOnlyTheHandlesTheServerResolved() {
        let segments = linked("hi @Alice and @bob, mail a@alice.com", "alice")
        #expect(segments.map(\.text) == ["hi ", "@Alice", " and @bob, mail a@alice.com"])
        #expect(segments.map(\.username) == [nil, "alice", nil])
    }

    @Test func aLongerHandleIsNotAPrefixMatch() {
        #expect(linked("@alice_2 hi", "alice").map(\.username) == [nil])
    }

    @Test func noMentionsMeansOneSegment() {
        #expect(linked("@alice hi").map(\.text) == ["@alice hi"])
    }
}

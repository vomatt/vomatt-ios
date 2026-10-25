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

import Testing
@testable import VomattCore

private func user(_ username: String) -> UserSummary { UserSummary(id: username, username: username) }

@Suite("Mention suggestions")
struct MentionTests {
    @Test func findsTheHandleTheCaretIsIn() {
        #expect(Mention.active(in: "hi @Wan", caret: 7) == ActiveMention(start: 3, term: "wan"))
    }

    @Test func findsABareAt() {
        #expect(Mention.active(in: "@", caret: 1) == ActiveMention(start: 0, term: ""))
    }

    @Test func ignoresAnAtInsideAWordLikeAnEmail() {
        #expect(Mention.active(in: "mail a@b", caret: 8) == nil)
        #expect(Mention.active(in: "萬@wan", caret: 5) == nil)
    }

    @Test func ignoresAHandleTheCaretHasLeft() {
        #expect(Mention.active(in: "@wan done", caret: 9) == nil)
    }

    @Test func ignoresAHandleLongerThanAUsername() {
        #expect(Mention.active(in: "@" + String(repeating: "a", count: 51), caret: 52) == nil)
    }

    @Test func replacesTheWholeHandleAlsoPastTheCaretAndAddsOneSpace() {
        let result = Mention.insert("wanan_chiang", into: "hi @wa_x there", replacing: ActiveMention(start: 3, term: "wa"))
        #expect(result.text == "hi @wanan_chiang there")
        #expect(result.caret == 17)
    }

    @Test func leavesTheViewerOutAndKeepsSix() {
        let found = ["klaus", "a", "b", "c", "d", "e", "f", "g"].map(user)
        #expect(Mention.suggestions(found, viewer: "Klaus").map(\.username) == ["a", "b", "c", "d", "e", "f"])
    }
}

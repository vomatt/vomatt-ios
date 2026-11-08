import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/app/poll/not-found.test.ts`.
@Suite("Poll id")
struct PollIDTests {
    @Test func acceptsAUUIDInEitherCase() {
        #expect(PollID.isValid("01a195a4-2a06-7137-a746-2c2ebb8136cc"))
        #expect(PollID.isValid("01A195A4-2A06-7137-A746-2C2EBB8136CC"))
    }

    @Test func rejectsALinkWhoseIdIsNotAPollId() {
        #expect(!PollID.isValid("does-not-exist"))
        #expect(!PollID.isValid("01a195a4-2a06-7137-a746-2c2ebb8136c"))
        #expect(!PollID.isValid("01a195a4-2a06-7137-a746-2c2ebb8136cc0"))
        #expect(!PollID.isValid(""))
    }
}

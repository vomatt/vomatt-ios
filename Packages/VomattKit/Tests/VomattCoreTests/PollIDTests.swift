import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/app/poll/not-found.test.ts` and `features/polls/shortId.test.ts`.
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

    @Test func writesTheSameShortIdAsTheWeb() {
        #expect(PollID.shortId("0199f2a3-5b7e-7d40-a1c8-9e3b2f6d4c05") == "31LUbIpAXJLg0ktOgLrEL")
        #expect(PollID.shortId("01A1F969-4E85-7F30-8E46-92D8AC4D3481") == "350umbhrmeH3RIf0E6JgP")
        #expect(PollID.shortId("ffffffff-ffff-ffff-ffff-ffffffffffff") == "7n42DGM5Tflk9n8mt7Fhc7")
        #expect(PollID.shortId("00000000-0000-0000-0000-000000000000") == "0")
        #expect(PollID.shortId("does-not-exist") == nil)
    }

    @Test func readsAShortIdBackToItsUUID() {
        #expect(PollID.fromShortId("31LUbIpAXJLg0ktOgLrEL") == "0199f2a3-5b7e-7d40-a1c8-9e3b2f6d4c05")
        #expect(PollID.fromShortId("7n42DGM5Tflk9n8mt7Fhc7") == "ffffffff-ffff-ffff-ffff-ffffffffffff")
    }

    @Test(arguments: ["031LUbIpAXJLg0ktOgLrEL", "7n42DGM5Tflk9n8mt7Fhc8", "zzzzzzzzzzzzzzzzzzzzzz", "31LUbIpAXJLg0ktOgLrE-", ""])
    func rejectsAShortIdTheWebWouldNotWrite(shortId: String) {
        #expect(PollID.fromShortId(shortId) == nil)
    }

    @Test func opensALinkByEitherForm() {
        let uuid = "0199f2a3-5b7e-7d40-a1c8-9e3b2f6d4c05"
        #expect(PollID.fromLink(uuid) == uuid)
        #expect(PollID.fromLink("31LUbIpAXJLg0ktOgLrEL") == uuid)
        #expect(PollID.fromLink("does-not-exist") == nil)
    }
}

import Testing
@testable import VomattCore

// Expected values computed with vomatt-web's seededUnit (src/features/polls/components/BallotMotion.tsx)

@Suite("Stamp angle")
struct StampAngleTests {
    @Test func seedsTheSameAngleAsTheWeb() {
        #expect(StampAngle.seeded("a") == 34.92)
        #expect(StampAngle.seeded("3f2b9c1e-7d4a-4e8b-9a6f-2c1d5e8b7a90") == 337.32)
        #expect(StampAngle.seeded("選項😀") == 146.88)
    }

    @Test func coversTheFullCircle() {
        #expect(StampAngle.angle(0) == 0)
        #expect(StampAngle.angle(0.5) == 180)
        #expect(StampAngle.angle(0.999) < 360)
    }
}

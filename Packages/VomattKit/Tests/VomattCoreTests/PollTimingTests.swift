import Foundation
import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/features/polls/timing.test.ts`: Wednesday 28 October 2026,
/// 10:00 in Taipei.
@Suite("Poll timing")
struct PollTimingTests {
    private static let taipei = TimeZone(identifier: "Asia/Taipei")!
    private static let now = taipei("2026-10-28T10:00:00")
    private static let started = taipei("2026-10-20T09:00:00")
    private static let hour: TimeInterval = 3600

    private static func taipei(_ local: String) -> Date {
        try! Date("\(local)+08:00", strategy: .iso8601)
    }

    private static func localizer(_ language: Language) throws -> Localizer {
        let locales = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../App/Resources/Locales").standardized
        func table(_ name: String) throws -> [String: String] {
            try Localizer.flatten(json: Data(contentsOf: locales.appending(path: "\(name).json")))
        }
        return Localizer(language: language, strings: try table(language.rawValue), fallback: try table("en"))
    }

    private func timing(_ language: Language, _ status: PollStatus, start: Date = started, end: Date?) throws -> PollTiming {
        PollTiming(
            startTime: start, endTime: end, status: status, now: Self.now,
            t: try Self.localizer(language), dates: DateFormatting(language: language, timeZone: Self.taipei)
        )
    }

    @Test func scheduledSaysTheSameOpensInChipAndMeta() throws {
        #expect(try timing(.en, .scheduled, start: Self.taipei("2026-11-02T09:00:00"), end: nil) == .init(chip: "Opens Mon 9:00", when: "Opens Mon 9:00"))
        #expect(try timing(.zh, .scheduled, start: Self.taipei("2026-11-02T09:00:00"), end: nil) == .init(chip: "週一 9:00 開始", when: "週一 9:00 開始"))
        #expect(try timing(.en, .scheduled, start: Self.taipei("2026-11-04T09:00:00"), end: nil) == .init(chip: "Opens Nov 4, 9:00", when: "Opens Nov 4, 9:00"))
        #expect(try timing(.zh, .scheduled, start: Self.taipei("2026-11-04T09:00:00"), end: nil) == .init(chip: "11月4日 9:00 開始", when: "11月4日 9:00 開始"))
        #expect(try timing(.en, .scheduled, start: Self.taipei("2026-10-29T09:00:00"), end: nil) == .init(chip: "Opens tomorrow at 9:00", when: "Opens tomorrow at 9:00"))
    }

    @Test func openNamesTheMoment() throws {
        #expect(try timing(.en, .open, end: Self.taipei("2026-10-30T20:00:00")) == .init(chip: "Ends Fri 20:00", when: "ends Fri 20:00"))
        #expect(try timing(.zh, .open, end: Self.taipei("2026-10-30T20:00:00")) == .init(chip: "週五 20:00 截止", when: "週五 20:00 結束"))
        #expect(try timing(.en, .open, end: Self.taipei("2026-11-06T20:00:00")) == .init(chip: "Ends Nov 6, 20:00", when: "ends Nov 6, 20:00"))
    }

    @Test func openWithoutAnEndIsTheWordAlone() throws {
        #expect(try timing(.en, .open, end: nil) == .init(chip: "Open", when: nil))
        #expect(try timing(.zh, .open, end: nil) == .init(chip: "進行中", when: nil))
    }

    @Test func closingUsesOneDuration() throws {
        let end = Self.now.addingTimeInterval(6 * Self.hour)
        #expect(try timing(.en, .closing, end: end) == .init(chip: "Ends in 6h", when: "ends in 6h"))
        #expect(try timing(.zh, .closing, end: end) == .init(chip: "6 小時後截止", when: "6 小時後截止"))
    }

    @Test func endedSaysTheDay() throws {
        #expect(try timing(.en, .ended, end: Self.taipei("2026-10-26T18:00:00")) == .init(chip: "Ended Mon", when: nil))
        #expect(try timing(.zh, .ended, end: Self.taipei("2026-10-26T18:00:00")) == .init(chip: "週一結束", when: nil))
        #expect(try timing(.en, .ended, end: Self.taipei("2026-10-21T18:00:00")) == .init(chip: "Ended Oct 21", when: nil))
        #expect(try timing(.en, .ended, end: Self.taipei("2026-10-27T18:00:00")) == .init(chip: "Ended yesterday", when: nil))
        #expect(try timing(.en, .ended, end: nil) == .init(chip: "Ended", when: nil))
        #expect(try timing(.zh, .ended, end: nil) == .init(chip: "已結束", when: nil))
    }

    @Test func durationRoundsUpAtTheUnitLines() {
        let en = DateFormatting(language: .en, timeZone: Self.taipei)
        #expect(en.duration(10) == "1m")
        #expect(en.duration(45 * 60) == "45m")
        #expect(en.duration(59.6 * 60) == "1h")
        #expect(en.duration(2 * 86_400) == "2d")
    }
}

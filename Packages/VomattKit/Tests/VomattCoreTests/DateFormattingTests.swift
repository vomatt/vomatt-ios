import Foundation
import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/features/polls/format.test.ts` (formatPollDay, formatAge).
@Suite("DateFormatting")
struct DateFormattingTests {
    private static let taipei: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()
    /// Wednesday 28 October 2026, 10:00 in Taipei, the web test's NOW.
    private static let now = local(2026, 10, 28, 10, 0)
    private static let en = DateFormatting(language: .en, timeZone: taipei.timeZone)
    private static let zh = DateFormatting(language: .zh, timeZone: taipei.timeZone)

    private static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        taipei.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test(arguments: [
        (local(2026, 10, 28, 23, 59), "today", "今天"),
        (local(2026, 10, 29, 0, 30), "tomorrow", "明天"),
        (local(2026, 10, 27, 18, 0), "yesterday", "昨天"),
        (local(2026, 10, 30, 20, 0), "Fri", "週五"),
        (local(2026, 11, 3, 9, 0), "Tue", "週二"),
        (local(2026, 10, 22, 9, 0), "Thu", "週四"),
        (local(2026, 11, 4, 9, 0), "Nov 4", "11月4日"),
        (local(2026, 10, 21, 9, 0), "Oct 21", "10月21日"),
        (local(2025, 10, 21, 9, 0), "Oct 21, 2025", "2025年10月21日"),
    ])
    func pollDayMatchesTheWeb(date: Date, english: String, chinese: String) {
        #expect(Self.en.pollDay(date, now: Self.now) == english)
        #expect(Self.zh.pollDay(date, now: Self.now) == chinese)
    }

    @Test func ageGivesTheDateFromAWeekOn() {
        #expect(Self.en.age(Self.local(2026, 10, 7, 12, 0), now: Self.now) == "Oct 7")
        #expect(Self.zh.age(Self.local(2026, 10, 7, 12, 0), now: Self.now) == "10月7日")
    }

    @Test func ageAddsTheYearToADateFromAnotherYear() {
        #expect(Self.en.age(Self.local(2025, 11, 2, 12, 0), now: Self.now) == "Nov 2, 2025")
        #expect(Self.zh.age(Self.local(2025, 11, 2, 12, 0), now: Self.now) == "2025年11月2日")
    }
}

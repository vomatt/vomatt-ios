import Foundation
import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/features/notifications/NotificationList.test.tsx`.
@Suite("Activity")
struct ActivityTests {
    private static let taipei: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
        return calendar
    }()
    private static let now = local(2026, 10, 26, 15, 0)
    private static let hour: TimeInterval = 3600

    private static func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        taipei.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func follow(_ name: String, minutesAgo: Double, read: Bool = false) -> FeedNotification {
        FeedNotification(
            id: "follow_\(name)", kind: .followed, createdAt: Self.now.addingTimeInterval(-minutesAgo * 60), read: read,
            actor: UserSummary(id: "u-\(name)", username: name)
        )
    }

    private func result(hoursAgo: Double) -> FeedNotification {
        FeedNotification(
            id: "result_p1", kind: .result, createdAt: Self.now.addingTimeInterval(-hoursAgo * Self.hour),
            poll: .init(id: "p1", title: "Keep the library open until 22:00?", isEnded: true)
        )
    }

    @Test func readsTodayYesterdayAndEarlierFromTheLocalCalendar() {
        let now = Self.local(2026, 10, 25, 12, 0)
        #expect(ActivityDay(Self.local(2026, 10, 25, 0, 5), now: now, calendar: Self.taipei) == .today)
        #expect(ActivityDay(Self.local(2026, 10, 24, 23, 59), now: now, calendar: Self.taipei) == .yesterday)
        #expect(ActivityDay(Self.local(2026, 10, 23, 12, 0), now: now, calendar: Self.taipei) == .earlier)
    }

    @Test func foldsConsecutiveFollowsIntoOneEntry() {
        let entries = ActivityEntry.entries([
            follow("bkim", minutesAgo: 10), follow("jtan", minutesAgo: 20), follow("tpark", minutesAgo: 30),
            result(hoursAgo: 4), follow("rosa", minutesAgo: 300),
        ])
        #expect(entries.map(\.id) == ["follow_bkim", "result_p1", "follow_rosa"])
        #expect(entries[0].items.map(\.id) == ["follow_bkim", "follow_jtan", "follow_tpark"])
        // A follow after another kind stands alone
        #expect(entries[2] == .single(follow("rosa", minutesAgo: 300)))
    }

    @Test func aGroupIsUnreadWhileAnyOfItsFollowsIs() {
        let group = ActivityEntry.follows([follow("bkim", minutesAgo: 10, read: true), follow("jtan", minutesAgo: 20)])
        #expect(group.isUnread)
        #expect(!ActivityEntry.follows([follow("bkim", minutesAgo: 10, read: true), follow("jtan", minutesAgo: 20, read: true)]).isUnread)
    }

    @Test func groupsByDayNewestFirst() {
        let sections = ActivitySection.sections(
            [follow("jtan", minutesAgo: 60), { var c = result(hoursAgo: 20); c.kind = .comment; return c }(), result(hoursAgo: 72)],
            now: Self.now, calendar: Self.taipei
        )
        #expect(sections.map(\.day) == [.today, .yesterday, .earlier])
        #expect(sections[2].entries.first?.items.first?.kind == .result)
    }

    @Test func leavesEmptyDaysOut() {
        #expect(ActivitySection.sections([result(hoursAgo: 72)], now: Self.now, calendar: Self.taipei).map(\.day) == [.earlier])
        #expect(ActivitySection.sections([], now: Self.now, calendar: Self.taipei).isEmpty)
    }

    @Test func ageMatchesTheWebsAuthorLine() {
        let en = DateFormatting(language: .en, timeZone: Self.taipei.timeZone)
        let zh = DateFormatting(language: .zh, timeZone: Self.taipei.timeZone)
        #expect(en.age(Self.now.addingTimeInterval(-30), now: Self.now) == "now")
        #expect(zh.age(Self.now.addingTimeInterval(-30), now: Self.now) == "剛剛")
        #expect(en.age(Self.now.addingTimeInterval(-45 * 60), now: Self.now) == "45m")
        #expect(en.age(Self.now.addingTimeInterval(-2.9 * Self.hour), now: Self.now) == "2h")
        #expect(zh.age(Self.now.addingTimeInterval(-2.9 * Self.hour), now: Self.now) == "2 小時")
        #expect(en.age(Self.now.addingTimeInterval(-3 * 24 * Self.hour), now: Self.now) == "3d")
        #expect(en.age(Self.local(2026, 10, 7, 9, 0), now: Self.now) == "Oct 7")
    }

    @Test func countUsesTheOneFormOnlyForOne() {
        let t = Localizer(
            language: .en,
            strings: ["n.followedYouGroup": "{name} and {count} others followed you", "n.followedYouGroup_one": "{name} and {count} other followed you"],
            fallback: [:]
        )
        #expect(t.count("n.followedYouGroup", 1, ["name": "@bkim"]) == "@bkim and 1 other followed you")
        #expect(t.count("n.followedYouGroup", 1200, ["name": "@bkim"]) == "@bkim and 1,200 others followed you")
    }
}

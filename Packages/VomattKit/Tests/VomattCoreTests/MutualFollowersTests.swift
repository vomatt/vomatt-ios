import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/features/profiles/MutualFollowers.test.tsx`.
@Suite("Mutual followers line")
struct MutualFollowersTests {
    private let t = Localizer(language: .en, strings: [
        "profile.mutualsOne": "Followed by @{name}",
        "profile.mutualsTwo": "Followed by @{name} and @{other}",
        "profile.mutualsMore": "Followed by @{name} and {count} others you follow",
        "profile.mutualsMore_one": "Followed by @{name} and {count} other you follow",
    ])
    private static let jtan = UserSummary(id: "u3", username: "jtan", displayName: "Jun Tan", avatarUrl: "bot:boba")
    private static let rosa = UserSummary(id: "u4", username: "rosa")
    private static let ken = UserSummary(id: "u5", username: "ken", displayName: "Ken")

    @Test(arguments: [
        (1, [jtan], "Followed by @jtan"),
        (2, [jtan, rosa], "Followed by @jtan and @rosa"),
        (3, [jtan, rosa, ken], "Followed by @jtan and 2 others you follow"),
        (1205, [jtan, rosa, ken], "Followed by @jtan and 1,204 others you follow"),
        // A preview short of the count still names only who it holds
        (2, [jtan], "Followed by @jtan and 1 other you follow"),
    ])
    func saysWhoIsInCommon(count: Int, preview: [UserSummary], text: String) {
        #expect(MutualFollowersLine(count: count, preview: preview, t: t)?.text == text)
    }

    @Test func picturesEachPersonItNamesTwoAtMost() {
        #expect(MutualFollowersLine(count: 1, preview: [Self.jtan], t: t)?.shown == [Self.jtan])
        #expect(MutualFollowersLine(count: 3, preview: [Self.jtan, Self.rosa, Self.ken], t: t)?.shown == [Self.jtan, Self.rosa])
    }

    @Test func showsNothingSignedOutOrOnTheirOwnProfile() {
        #expect(MutualFollowersLine(count: nil, preview: [], t: t) == nil)
    }

    @Test func showsNothingWithNoOneInCommon() {
        #expect(MutualFollowersLine(count: 0, preview: [], t: t) == nil)
    }
}

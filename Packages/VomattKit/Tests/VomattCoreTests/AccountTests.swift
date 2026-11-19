import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/features/account/visibility.test.ts`.
@Suite("Profile visibility")
struct ProfileVisibilityTests {
    @Test func followsTheSavedSetting() {
        #expect(!ProfileVisibility.isPublic(["displayName": false, "location": true], "displayName"))
        #expect(ProfileVisibility.isPublic(["displayName": false, "location": true], "location"))
    }

    @Test func fallsBackToTheAPIDefaults() {
        #expect(ProfileVisibility.isPublic([:], "displayName"))
        #expect(ProfileVisibility.isPublic([:], "bio"))
        #expect(!ProfileVisibility.isPublic([:], "points"))
    }

    @Test func changesListOnlyTheFieldsWhoseVisibilityChanged() {
        let changes = ProfileVisibility.changes(saved: ["bio": true], next: ["bio": true, "firstName": true, "displayName": false])
        #expect(changes == ["firstName": true, "displayName": false])
    }

    @Test func changesNeverSendTheFieldsNoPageShows() {
        #expect(ProfileVisibility.changes(saved: [:], next: ["location": true, "points": true, "membershipLevel": true]).isEmpty)
    }

    @Test func changesAreEmptyWhenNothingChanged() {
        #expect(ProfileVisibility.changes(saved: [:], next: ["displayName": true, "points": false]).isEmpty)
    }

    // The web's OwnProfileView: the header locks hidden fields that have a value
    @Test func hiddenFieldsAreTheHiddenOnesWithAValue() {
        let profile = MyProfile(
            id: "1", username: "klaus", displayName: "Klaus", bio: "", firstName: "Klaus",
            visibilitySettings: ["displayName": false, "bio": false, "location": true]
        )
        #expect(profile.hiddenFields == ["displayName", "firstName"])
    }

    @Test func aGenderIsHiddenUntilItsOwnerShowsIt() {
        #expect(MyProfile(id: "1", username: "klaus", gender: .other).hiddenFields == ["gender"])
        #expect(MyProfile(id: "1", username: "klaus", visibilitySettings: ["gender": true], gender: .other).hiddenFields.isEmpty)
        #expect(MyProfile(id: "1", username: "klaus").hiddenFields.isEmpty)
    }

    @Test func theOwnersHeaderGetsTheirGender() {
        #expect(MyProfile(id: "1", username: "klaus", gender: .female).asOwnProfile.gender == .female)
    }

    // The web's AccountSettings: one per Edit profile setting, the real name shown when either half is
    @Test func shownSettingsCountTheRealNameOnce() {
        #expect(MyProfile(id: "1", username: "klaus").shownSettingCount == 2)
        #expect(MyProfile(id: "1", username: "klaus", visibilitySettings: ["lastName": true, "bio": false]).shownSettingCount == 2)
        #expect(ProfileVisibility.settings.count == 4)
    }

    @Test func settingsAreRealNameThenDisplayNameThenGenderThenBio() {
        #expect(ProfileVisibility.settings.map(\.key) == ["realName", "displayName", "gender", "bio"])
        #expect(ProfileVisibility.settings[0].fields == ["firstName", "lastName"])
    }

    // The web's VisibilitySettings: the real name and gender hidden, the rest public by default
    @Test func settingsFallBackToTheAPIDefaults() {
        #expect(ProfileVisibility.settings.map { ProfileVisibility.isPublic([:], $0) } == [false, true, false, true])
    }

    @Test func realNameIsShownWhenEitherHalfIs() {
        let realName = ProfileVisibility.settings[0]
        #expect(ProfileVisibility.isPublic(["firstName": false, "lastName": true], realName))
        #expect(ProfileVisibility.isPublic(["firstName": true], realName))
        #expect(!ProfileVisibility.isPublic(["firstName": false, "lastName": false], realName))
    }
}

/// Ported from vomatt-web `src/__tests__/features/account/username.test.ts`.
@Suite("Username rule")
struct UsernameRuleTests {
    @Test func acceptsLowercaseLettersNumbersAndUnderscores() {
        #expect(Username.isValid("chinssiang_3797"))
        #expect(Username.isValid(String(repeating: "a", count: 50)))
    }

    @Test func rejectsNamesTooShortTooLongOrWithOtherCharacters() {
        #expect(!Username.isValid("ab"))
        #expect(!Username.isValid(String(repeating: "a", count: 51)))
        #expect(!Username.isValid("no spaces"))
        #expect(!Username.isValid("dot.name"))
        #expect(!Username.isValid("Alice"))
    }

    @Test func rejectsTheReservedNamesTheAPIRefuses() {
        for name in Username.reserved { #expect(!Username.isValid(name), "\(name)") }
        #expect(Username.reserved.contains("following"))
        #expect(Username.reserved.contains("signup"))
    }

    @Test func rejectsTheRootPagesThatRedirectToTheAboutSite() {
        #expect(!Username.isValid("about"))
        #expect(!Username.isValid("contact"))
    }

    @Test func acceptsNamesThatOnlyStartWithAReservedName() {
        #expect(Username.isValid("searcher"))
        #expect(Username.isValid("admins"))
        #expect(Username.isValid("mine"))
    }

    @Test func matchesTheViewerRegardlessOfCase() {
        #expect(Username.isOwn("Klaus", me: "klaus"))
        #expect(!Username.isOwn("klaus2", me: "klaus"))
        #expect(!Username.isOwn("klaus", me: nil))
    }
}

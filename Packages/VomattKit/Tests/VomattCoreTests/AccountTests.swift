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
        let changes = ProfileVisibility.changes(saved: ["bio": true], next: ["bio": true, "location": true, "displayName": false])
        #expect(changes == ["location": true, "displayName": false])
    }

    @Test func changesAreEmptyWhenNothingChanged() {
        #expect(ProfileVisibility.changes(saved: [:], next: ["displayName": true, "points": false]).isEmpty)
    }

    // The web's OwnProfileView: the header locks hidden fields that have a value
    @Test func hiddenFieldsAreTheHiddenOnesWithAValue() {
        let profile = MyProfile(
            id: "1", username: "klaus", displayName: "Klaus", bio: "", firstName: "Klaus", location: "Taipei",
            points: 0, visibilitySettings: ["displayName": false, "bio": false, "location": true]
        )
        #expect(profile.hiddenFields == ["displayName", "firstName", "points"])
        #expect(profile.shownFieldCount == 1)
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

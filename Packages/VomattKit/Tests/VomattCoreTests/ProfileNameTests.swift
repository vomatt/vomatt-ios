import Testing
@testable import VomattCore

/// Ported from vomatt-web `src/__tests__/features/profiles/name.test.ts`.
@Suite("Profile name")
struct ProfileNameTests {
    @Test func leadsWithTheRealNameAndFollowsItWithTheDisplayName() {
        let name = ProfileName(username: "mei", displayName: "Meimei", firstName: "Mei", lastName: "Lin")
        #expect(name == ProfileName(primary: "Mei Lin", secondary: "Meimei"))
    }

    @Test func writesAChineseNameFamilyNameFirstWithNoSpace() {
        #expect(ProfileName(username: "mei", firstName: "小明", lastName: "陳").primary == "陳小明")
    }

    @Test func writesAKoreanNameFamilyNameFirstWithNoSpace() {
        #expect(ProfileName(username: "mj", firstName: "민준", lastName: "김").primary == "김민준")
    }

    @Test func keepsGivenNameFirstWhenOnlyOnePartIsChinese() {
        #expect(ProfileName(username: "mei", firstName: "Mei", lastName: "林").primary == "Mei 林")
    }

    @Test func showsADisplayNameThatRepeatsTheRealNameOnce() {
        let name = ProfileName(username: "mei", displayName: "mei lin", firstName: "Mei", lastName: "Lin")
        #expect(name == ProfileName(primary: "Mei Lin", secondary: nil))
    }

    @Test func showsTheRealNameAloneWhenThereIsNoDisplayName() {
        let name = ProfileName(username: "mei", displayName: "", firstName: "Mei", lastName: "Lin")
        #expect(name == ProfileName(primary: "Mei Lin", secondary: nil))
    }

    @Test func usesWhicheverHalfOfTheRealNameIsSet() {
        #expect(ProfileName(username: "mei", lastName: "Lin").primary == "Lin")
    }

    @Test func showsTheDisplayNameWhenThereIsNoRealName() {
        let name = ProfileName(username: "mei", displayName: "Meimei", firstName: nil, lastName: "  ")
        #expect(name == ProfileName(primary: "Meimei", secondary: nil))
    }

    @Test func fallsBackToTheUsername() {
        #expect(ProfileName(username: "mei", displayName: nil) == ProfileName(primary: "mei", secondary: nil))
    }
}

/// The name step's cases from vomatt-web `src/__tests__/components/AuthDialog.test.tsx`.
@Suite("Sign-up name")
struct SignUpNameTests {
    @Test func takesTheFirstAndLastName() {
        let name = SignUpName(firstName: " New ", lastName: "Bie ")
        #expect(name?.firstName == "New" && name?.lastName == "Bie")
    }

    @Test func needsAFirstNameButNotALastName() {
        #expect(SignUpName(firstName: "  ", lastName: "Bie") == nil)
        let name = SignUpName(firstName: "Cher", lastName: " ")
        #expect(name?.firstName == "Cher" && name?.lastName == nil)
    }
}

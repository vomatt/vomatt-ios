import XCTest

/// Walks the signed-out app against the configured API: feed, ballot, sign-in gate,
/// poll detail, Explore, profile and settings. Screenshots are kept in the test result.
@MainActor
final class SmokeTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-preferred-language", "en", "-reset-session"]
        app.launch()
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFeedBallotAndSignInGate() {
        // The tab bar is custom, so its items are plain buttons
        XCTAssertTrue(app.buttons["Explore"].waitForExistence(timeout: 10))
        let vote = app.buttons["Vote"].firstMatch
        XCTAssertTrue(vote.waitForExistence(timeout: 20), "the feed should show an open poll")
        snapshot("1-feed")

        // Picking an option enables Vote; voting signed out asks to sign in
        XCTAssertFalse(vote.isEnabled)
        let option = app.buttons.matching(identifier: "ballot-option").firstMatch
        XCTAssertTrue(option.exists)
        option.tap()
        snapshot("2-option-selected")
        XCTAssertTrue(vote.isEnabled)
        vote.tap()
        XCTAssertTrue(app.staticTexts["Log in or sign up"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["Email"].exists)
        snapshot("3-sign-in")

        // A malformed address is caught before anything is sent
        app.textFields["Email"].tap()
        app.typeText("not-an-email")
        app.buttons["Continue with email"].tap()
        XCTAssertTrue(app.staticTexts["Invalid email address"].waitForExistence(timeout: 3))
        snapshot("4-sign-in-error")
        app.buttons["Close"].tap()
    }

    func testPollDetailExploreAndProfile() {
        XCTAssertTrue(app.buttons["Vote"].firstMatch.waitForExistence(timeout: 20))

        // A poll title opens its page with the about panel and discussion
        app.buttons.matching(identifier: "poll-title").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["ABOUT THIS POLL"].waitForExistence(timeout: 10))
        snapshot("5-poll-detail")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Discussion'")).firstMatch.waitForExistence(timeout: 10))
        snapshot("6-poll-discussion")

        // On iOS 26 the tab bar shrinks while scrolling down; scrolling back up brings it back
        if #available(iOS 26, *) { app.swipeDown() }
        app.buttons["Explore"].tap()
        XCTAssertTrue(app.staticTexts["Explore"].waitForExistence(timeout: 5))
        app.buttons["Ended"].firstMatch.tap()
        sleep(3)
        snapshot("7-explore-ended")

        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.staticTexts["Log in or sign up for Vomatt"].waitForExistence(timeout: 5))

        app.buttons["Profile"].tap()
        // Signed out, Profile offers sign-in and the legal links
        XCTAssertTrue(app.buttons["Terms"].firstMatch.waitForExistence(timeout: 5))
        snapshot("8-profile-signed-out")
    }

    func testBlockingHidesTheirPolls() {
        let title = app.buttons.matching(identifier: "poll-title").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        let label = title.label
        title.press(forDuration: 1.0)
        let block = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Block '")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5))
        snapshot("9-block-menu")
        block.tap()
        // Blocking asks first
        let confirm = app.alerts.buttons["Block"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        snapshot("9b-block-confirm")
        confirm.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'is blocked'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier == 'poll-title' AND label == %@", label)).firstMatch.exists)
    }

    func testCreateAsksToSignIn() {
        XCTAssertTrue(app.buttons["Create a poll"].waitForExistence(timeout: 10))
        app.buttons["Create a poll"].tap()
        XCTAssertTrue(app.staticTexts["Log in or sign up"].waitForExistence(timeout: 5))
    }
}

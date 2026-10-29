import XCTest

/// Sign up, create, vote, comment and sign out against a local vomatt-api with
/// `EMAIL_ENABLED=false`. Skipped unless `E2E_OTP_DIR` names a folder where a helper
/// writes each email's one-time code (see docs/e2e.md); run with
/// `TEST_RUNNER_E2E_OTP_DIR=… make test-ui` and a Debug build pointed at that API.
@MainActor
final class SignedInFlowTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["E2E_OTP_DIR"] != nil else {
            throw XCTSkip("Set TEST_RUNNER_E2E_OTP_DIR to run the signed-in flow against a local API")
        }
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

    private func code(for email: String) throws -> String {
        let folder = ProcessInfo.processInfo.environment["E2E_OTP_DIR"]!
        // scripts/e2e-otp.py answers each `.want` with the code
        FileManager.default.createFile(atPath: "\(folder)/\(email).want", contents: nil)
        let path = "\(folder)/\(email).txt"
        for _ in 0..<40 {
            if let code = try? String(contentsOfFile: path, encoding: .utf8), code.count == 6 { return code }
            Thread.sleep(forTimeInterval: 0.5)
        }
        throw XCTSkip("No code appeared at \(path)")
    }

    func testSignUpCreateVoteCommentSignOut() throws {
        let email = "ios-e2e-\(Int(Date().timeIntervalSince1970))@example.com"
        let question = "Which night market should we visit? \(Int.random(in: 100...999))"

        // Creating asks a guest to sign in first, then continues to the creator
        XCTAssertTrue(app.buttons["Create a poll"].waitForExistence(timeout: 10))
        app.buttons["Create a poll"].tap()
        app.textFields["Email"].tap()
        app.typeText(email)
        app.buttons["Continue with email"].tap()

        XCTAssertTrue(app.staticTexts["Check your email"].waitForExistence(timeout: 10))
        snapshot("e2e-1-code")
        app.textFields["6-digit verification code"].tap()
        app.typeText(try code(for: email))

        // A new account names itself
        XCTAssertTrue(app.staticTexts["What should we call you?"].waitForExistence(timeout: 10))
        app.buttons["Finish"].tap()

        // The creator opens once signed in
        let questionField = app.textFields["What do you want people to weigh in on?"]
        XCTAssertTrue(questionField.waitForExistence(timeout: 10))
        questionField.tap()
        app.typeText(question)
        app.textFields["Option 1"].tap()
        app.typeText("Raohe\n")
        app.typeText("Ningxia")
        snapshot("e2e-2-creator")
        app.buttons["Review"].tap()
        XCTAssertTrue(app.staticTexts["How voters will see it"].waitForExistence(timeout: 5))
        snapshot("e2e-3-review")
        app.buttons["Publish poll"].tap()

        // Lands on the new poll
        XCTAssertTrue(app.staticTexts["Asked by"].waitForExistence(timeout: 15))
        app.buttons.matching(identifier: "ballot-option").element(boundBy: 1).tap()
        app.buttons["Vote"].tap()
        XCTAssertTrue(app.staticTexts["VOTED"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Withdraw vote"].exists)
        snapshot("e2e-4-voted")

        // Discussion
        app.swipeUp()
        let composer = app.textFields["Why did you vote the way you did?"]
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap()
        app.typeText("Raohe has the best pepper buns.")
        app.buttons["Post"].tap()
        XCTAssertTrue(app.staticTexts["Raohe has the best pepper buns."].waitForExistence(timeout: 10))
        snapshot("e2e-5-commented")

        // Profile, whose Asked tab lists it as Open now, then sign out from Settings
        app.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["polls voted in"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[question].waitForExistence(timeout: 10))
        snapshot("e2e-6-account")
        app.buttons["Settings"].tap()
        app.swipeUp()
        app.buttons["Log out"].firstMatch.tap()
        app.sheets.buttons["Log out"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Log in or sign up for Vomatt"].waitForExistence(timeout: 10))
    }

    /// A wrong code stays explained and keeps the keyboard; the 3rd locks the email for this IP.
    func testWrongCodeStaysVisibleThenLocks() throws {
        let email = "ios-wrong-\(Int(Date().timeIntervalSince1970))@example.com"
        XCTAssertTrue(app.buttons["Create a poll"].waitForExistence(timeout: 10))
        app.buttons["Create a poll"].tap()
        app.textFields["Email"].tap()
        app.typeText(email)
        app.buttons["Continue with email"].tap()
        XCTAssertTrue(app.staticTexts["Check your email"].waitForExistence(timeout: 10))
        let wrong = try code(for: email) == "000000" ? "111111" : "000000"

        app.typeText(wrong)
        let invalid = app.staticTexts["That code is not right. Check the email and try again."]
        XCTAssertTrue(invalid.waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(invalid.exists, "the error should not flash away")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "the keyboard should stay up to retry")

        app.typeText(wrong)
        _ = invalid.waitForExistence(timeout: 5)
        app.typeText(wrong)
        let locked = app.staticTexts["Too many wrong attempts. Try again in 15 minutes."]
        XCTAssertTrue(locked.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["6-digit verification code"].isEnabled)
        snapshot("e2e-wrong-code-locked")

        // The lockout also refuses a new code while it lasts (vomatt-api #44), so the field stays locked
        app.buttons["Resend verification code"].tap()
        XCTAssertTrue(locked.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["6-digit verification code"].isEnabled)
    }

    /// The access token lives 120s on the test API; a request after the refresh leeway rotates it once.
    func testSessionSurvivesTokenRefresh() throws {
        let email = "ios-refresh-\(Int(Date().timeIntervalSince1970))@example.com"
        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 10))
        app.buttons["Profile"].tap()
        app.buttons["Log in"].firstMatch.tap()
        app.textFields["Email"].tap()
        app.typeText(email)
        app.buttons["Continue with email"].tap()
        XCTAssertTrue(app.staticTexts["Check your email"].waitForExistence(timeout: 10))
        app.textFields["6-digit verification code"].tap()
        app.typeText(try code(for: email))
        XCTAssertTrue(app.staticTexts["What should we call you?"].waitForExistence(timeout: 10))
        app.buttons["Skip for now"].tap()
        XCTAssertTrue(app.staticTexts["polls voted in"].waitForExistence(timeout: 10))

        // Past the 60s refresh leeway of a 120s token
        Thread.sleep(forTimeInterval: 70)
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Invite lists"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Log in or sign up for Vomatt"].exists, "the session should have been refreshed, not ended")
        app.buttons["Profile"].tap()
        XCTAssertTrue(app.staticTexts["polls voted in"].waitForExistence(timeout: 10))
    }
}

import Foundation
import Testing
@testable import VomattCore

@Suite("Localizer")
struct LocalizerTests {
    private let localizer = Localizer(
        language: .zh,
        strings: ["poll.voted": "{count} 人已投票", "only.zh": "中文"],
        fallback: ["poll.voted": "{count} voted", "only.en": "English"]
    )

    @Test func interpolatesPlaceholders() {
        #expect(localizer("poll.voted", ["count": 3]) == "3 人已投票")
    }

    @Test func fallsBackToEnglishThenTheKey() {
        #expect(localizer("only.en") == "English")
        #expect(localizer("missing.key") == "missing.key")
    }

    @Test func unknownPlaceholdersStay() {
        #expect(Localizer.interpolate("{a} and {b}", ["a": 1]) == "1 and {b}")
        #expect(Localizer.interpolate("no braces", ["a": 1]) == "no braces")
    }

    @Test func flattensNestedJSON() throws {
        let json = #"{"poll":{"vote":"Vote","audience":{"public":"Public"}},"top":"T"}"#
        let flat = try Localizer.flatten(json: Data(json.utf8))
        #expect(flat == ["poll.vote": "Vote", "poll.audience.public": "Public", "top": "T"])
    }

    // From vomatt-web's format.test.ts `joinSentences`
    @Test func separatesEnglishSentencesWithASpace() {
        #expect(Localizer(language: .en, strings: [:]).sentences("Anyone can vote.", "Only you will see.")
            == "Anyone can vote. Only you will see.")
    }

    @Test func runsChineseSentencesTogether() {
        #expect(Localizer(language: .zh, strings: [:]).sentences("任何人都能投票。", "只有你會看到。") == "任何人都能投票。只有你會看到。")
    }

    @Test func preferredLanguage() {
        #expect(Language.preferred(["zh-Hant-TW", "en"]) == .zh)
        #expect(Language.preferred(["fr", "en-GB"]) == .en)
        #expect(Language.preferred(["fr"]) == .en)
        #expect(Language.zh.localeIdentifier == "zh-TW")
    }
}

@Suite("Dates")
struct DateTests {
    @Test func lenientTranscoderReadsEveryAPIFormat() throws {
        let transcoder = LenientDateTranscoder()
        let micro = try transcoder.decode("2026-10-13T15:04:58.14499Z")
        let whole = try transcoder.decode("2026-10-20T15:04:00Z")
        let offset = try transcoder.decode("2026-10-12T09:00:00+08:00")
        #expect(abs(micro.timeIntervalSince1970 - 1_791_903_898.144) < 0.001)
        #expect(whole.timeIntervalSince1970 == 1_792_508_640)
        #expect(offset.timeIntervalSince1970 == 1_791_766_800)
        #expect(throws: (any Error).self) { try transcoder.decode("yesterday") }
        #expect(try transcoder.encode(whole) == "2026-10-20T15:04:00Z")
    }

    @Test func pollDateUsesTheReadersTimeZone() {
        let date = try! LenientDateTranscoder().decode("2026-10-07T14:00:00Z")
        let taipei = DateFormatting(language: .en, timeZone: TimeZone(identifier: "Asia/Taipei")!)
        #expect(taipei.pollDate(date) == "Oct 7, 22:00")
        let chinese = DateFormatting(language: .zh, timeZone: TimeZone(identifier: "Asia/Taipei")!)
        #expect(chinese.pollDate(date) == "10月7日 22:00")
        #expect(chinese.monthYear(date) == "2026年10月")
    }

    @Test func fromNowUsesWholeUnits() {
        let now = Date(timeIntervalSince1970: 0)
        let english = DateFormatting(language: .en)
        #expect(english.fromNow(now.addingTimeInterval(5 * 3600), now: now) == "in 5 hours")
        #expect(english.fromNow(now.addingTimeInterval(-2 * 86_400), now: now) == "2 days ago")
    }
}

@Suite("Access token claims")
struct TokenClaimTests {
    static func token(sub: String, exp: TimeInterval) -> String {
        let payload = try! JSONSerialization.data(withJSONObject: ["sub": sub, "exp": exp])
        let encoded = payload.base64EncodedString().replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        return "eyJhbGciOiJIUzI1NiJ9.\(encoded).signature"
    }

    @Test func readsSubjectAndExpiry() {
        let claims = AccessTokenClaims(token: Self.token(sub: "user-1", exp: 1000))
        #expect(claims.subject == "user-1")
        #expect(claims.isExpiringSoon(leeway: 60, now: Date(timeIntervalSince1970: 950)))
        #expect(!claims.isExpiringSoon(leeway: 60, now: Date(timeIntervalSince1970: 900)))
        #expect(AccessTokenClaims(token: "garbage").subject == nil)
    }
}

@Suite("Auth error keys")
struct AuthErrorKeyTests {
    @Test func mapsCodesThenStatus() {
        #expect(AuthErrorKey(APIError(.http(400), errorCode: "auth.invalid_otp")) == .invalidCode)
        #expect(AuthErrorKey(APIError(.http(429))) == .rateLimited)
        #expect(AuthErrorKey(APIError(.http(400))) == .invalidEmail)
        #expect(AuthErrorKey(APIError(.network)) == .serverError)
        #expect(AuthErrorKey.codeExpired.translationKey == "authError.codeExpired")
    }
}

// Cases ported from vomatt-web's UnreadCount.test.tsx (formatUnreadCount)
@Suite("Unread count")
struct UnreadCountTests {
    @Test func theAPICapReadsAs99Plus() { #expect(formatUnreadCount(100) == "99+") }
    @Test func countsBelowTheCapAreExact() { #expect(formatUnreadCount(99) == "99") }
}

@Suite("API error messages")
struct APIErrorMessageTests {
    private let t = Localizer(
        language: .zh,
        strings: [
            "apiError.vote.ended": "投票已結束，無法再投票或撤回",
            "apiError.vote.options.min": "至少需要 {0} 個選項",
            "groups.saveFailed": "儲存失敗",
        ],
        fallback: [:]
    )

    @Test func knownCodeUsesTheAppString() {
        let error = APIError(.http(400), errorCode: "vote.ended", message: "Poll ended")
        #expect(t.message(for: error, fallback: "groups.saveFailed") == "投票已結束，無法再投票或撤回")
    }

    @Test func codeWithAValuePrefersTheAPIMessage() {
        let error = APIError(.http(400), errorCode: "vote.options.min", message: "至少需要 2 個選項")
        #expect(t.message(for: error, fallback: "groups.saveFailed") == "至少需要 2 個選項")
        #expect(t.message(for: APIError(.http(400), errorCode: "vote.options.min"), fallback: "groups.saveFailed") == "儲存失敗")
    }

    @Test func detailedCodePrefersTheAPIMessage() {
        let t = Localizer(language: .en, strings: ["apiError.common.validation_failed": "Validation failed"])
        let error = APIError(.http(400), errorCode: "common.validation_failed", message: "title: size must be between 1 and 200")
        #expect(t.message(for: error, fallback: "x") == "title: size must be between 1 and 200")
        #expect(t.message(for: APIError(.http(400), errorCode: "common.validation_failed"), fallback: "x") == "Validation failed")
    }

    @Test func localeFilesShareTheSameCodesAndPlaceholders() throws {
        let locales = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../App/Resources/Locales").standardized
        func table(_ name: String) throws -> [String: String] {
            try Localizer.flatten(json: Data(contentsOf: locales.appending(path: "\(name).json")))
                .filter { $0.key.hasPrefix("apiError.") }
        }
        func placeholders(_ text: String) -> [String] {
            text.matches(of: /\{[A-Za-z0-9_-]+\}/).map { String($0.output) }.sorted()
        }
        let en = try table("ios.en"), zh = try table("ios.zh")
        #expect(!en.isEmpty)
        #expect(Set(en.keys) == Set(zh.keys))
        for (key, text) in en { #expect(placeholders(text) == placeholders(zh[key] ?? ""), "\(key)") }
    }

    // A 409 `common.conflict` changed nothing; the web words it as busy, not as a conflict
    @Test func conflictSaysBusyInTheShippedStrings() throws {
        let locales = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../../../App/Resources/Locales").standardized
        let bundle = try #require(Bundle(url: locales))
        let error = APIError(.http(409), errorCode: "common.conflict", message: "Resource conflict, please try again")
        #expect(Localizer.load(.en, bundle: bundle).message(for: error, fallback: "account.saveFailed")
            == "Another change is in progress. Try again in a moment.")
        #expect(Localizer.load(.zh, bundle: bundle).message(for: error, fallback: "account.saveFailed") == "目前有其他變更正在進行，請稍後再試。")
    }

    @Test func unknownCodeUsesTheAPIMessageThenTheFallback() {
        #expect(t.message(for: APIError(.http(400), errorCode: "new.code", message: "新錯誤"), fallback: "groups.saveFailed") == "新錯誤")
        #expect(t.message(for: APIError(.http(500)), fallback: "groups.saveFailed") == "儲存失敗")
    }

    @Test func transportFailuresUseTheFallback() {
        #expect(t.message(for: APIError(.network, message: "The Internet connection appears to be offline."), fallback: "groups.saveFailed") == "儲存失敗")
        #expect(t.message(for: CancellationError(), fallback: "groups.saveFailed") == "儲存失敗")
    }
}

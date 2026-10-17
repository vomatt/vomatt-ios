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

import Foundation

/// Every failure the service throws. Branch on `errorCode` (the API's stable,
/// dotted code), never on `message`, which is localized for display.
public struct APIError: Error, Equatable, Sendable, LocalizedError {
    public enum Kind: Equatable, Sendable {
        /// The API answered with this HTTP status.
        case http(Int)
        /// No session, or the API refused it and it couldn't be refreshed.
        case notAuthenticated
        /// The request never got an answer.
        case network
        /// The answer didn't have the shape the contract promises.
        case decoding
    }

    public var kind: Kind
    public var errorCode: String?
    public var message: String?
    /// Seconds to wait before retrying, from a 429's `Retry-After`.
    public var retryAfter: Int?

    public init(_ kind: Kind, errorCode: String? = nil, message: String? = nil, retryAfter: Int? = nil) {
        self.kind = kind
        self.errorCode = errorCode
        self.message = message
        self.retryAfter = retryAfter
    }

    public var status: Int? {
        if case let .http(status) = kind { return status }
        return nil
    }

    public var errorDescription: String? { message ?? errorCode }

    /// 429: e.g. more than 30 Ballot writes a minute.
    public var isRateLimited: Bool { status == 429 }
    /// A Ballot arrived after the Poll Ended.
    public var isPollEnded: Bool { errorCode == "vote.ended" }
    /// 409: the Poll stayed busy with other changes; nothing was recorded.
    public var isBusy: Bool { errorCode == "common.conflict" }
    /// Results are sealed while the Poll is Open; `/results` answers 403.
    public var isSealed: Bool { status == 403 }
    public var isNotFound: Bool { status == 404 }
    /// The token still verifies but its account was deleted (on another device, say): treat it as signed out.
    public var isAccountGone: Bool { errorCode == "user.not_found" }
}

/// Keys under `authError.*` in the locale files.
public enum AuthErrorKey: String, Sendable {
    case invalidCode, codeExpired, tooManyAttempts, resendCooldown, emailSendFailed
    case accountSuspended, rateLimited, invalidEmail, serverError, passkeyInvalid

    private static let codes: [String: AuthErrorKey] = [
        "auth.invalid_otp": .invalidCode,
        "auth.otp.invalid_or_expired": .codeExpired,
        "auth.otp.expired": .codeExpired,
        "auth.otp.too_many_attempts": .tooManyAttempts,
        "auth.otp.resend_cooldown": .resendCooldown,
        "auth.email.send_failed": .emailSendFailed,
        "auth.account_banned": .accountSuspended,
        "auth.passkey.invalid": .passkeyInvalid,
    ]

    /// Maps a backend `errorCode` and HTTP status to a message the UI can show.
    public init(_ error: Error) {
        guard let error = error as? APIError else { self = .serverError; return }
        if let code = error.errorCode, let key = Self.codes[code] { self = key; return }
        switch error.status {
        case 429: self = .rateLimited
        case 400: self = .invalidEmail
        default: self = .serverError
        }
    }

    /// A failed passkey sign-in; nil when the person cancelled, which isn't an error to show.
    public init?(passkeyError error: Error) {
        if isPasskeyCancellation(error) { return nil }
        self.init(error)
    }

    public var translationKey: String { "authError.\(rawValue)" }
}

import Foundation
import HTTPTypes
import OpenAPIRuntime
import os
import VomattAPI

/// Turns every non-2xx answer into an `APIError` read from the error envelope
/// (`{ success, message, errorCode }`), so callers only ever see success bodies.
/// Outermost, so it sees the answer after any auth retry.
struct ErrorEnvelopeMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard response.status.kind != .successful else { return (response, responseBody) }

        var errorCode: String?
        var message: String?
        if let responseBody, let data = try? await Data(collecting: responseBody, upTo: 1 << 20),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            errorCode = json["errorCode"] as? String
            message = json["message"] as? String
        }
        let retryAfter = response.headerFields[.retryAfter].flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
        throw APIError(.http(response.status.code), errorCode: errorCode, message: message, retryAfter: retryAfter)
    }
}

/// Leaves out of the notification feed every item whose `kind` this build doesn't know, and an unknown
/// `category`, before the generated decoder sees them: its enums reject unknown values, which would fail
/// the whole page. The web's `getNotifications` skips them the same way.
struct UnknownNotificationKindsMiddleware: ClientMiddleware {
    private static let kinds = Set(Schemas.NotificationResponse.KindPayload.allCases.map(\.rawValue))
    private static let categories = Set(Schemas.NotificationResponse.CategoryPayload.allCases.map(\.rawValue))

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (response, responseBody) = try await next(request, body, baseURL)
        guard operationID == Operations.List.id, response.status.kind == .successful, let responseBody else {
            return (response, responseBody)
        }
        let data = try await Data(collecting: responseBody, upTo: 8 << 20)
        return (response, HTTPBody(Self.known(data)))
    }

    private static func known(_ data: Data) -> Data {
        guard var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var page = json["data"] as? [String: Any],
              let items = page["items"] as? [[String: Any]]
        else { return data }
        page["items"] = items.compactMap { item -> [String: Any]? in
            guard let kind = item["kind"] as? String, kinds.contains(kind) else { return nil }
            guard let category = item["category"] as? String, !categories.contains(category) else { return item }
            var item = item
            item["category"] = nil
            return item
        }
        json["data"] = page
        return (try? JSONSerialization.data(withJSONObject: json)) ?? data
    }
}

/// Sends the session's access token, refreshed shortly before it expires. On a 401 it
/// refreshes once and retries; when the session is over it retries without a token,
/// which public endpoints still answer.
struct AuthMiddleware: ClientMiddleware {
    let session: Session

    /// Operations that carry their own credentials, or none.
    static let unauthenticated: Set<String> = [
        "refresh", "logout", "sendOtp", "verifyOtp",
        "phoneSendOtp", "phoneVerifyOtp", "appleLogin", "googleLogin", "lineLogin",
        "passkeyLoginOptions", "passkeyLoginVerify",
    ]

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        guard !Self.unauthenticated.contains(operationID), let token = await session.accessToken() else {
            return try await next(request, body, baseURL)
        }
        var authed = request
        authed.headerFields[.authorization] = "Bearer \(token)"
        let (response, responseBody) = try await next(authed, body, baseURL)
        guard response.status == .unauthorized else { return (response, responseBody) }

        if let retryToken = await session.accessTokenAfterRejection(of: token) {
            authed.headerFields[.authorization] = "Bearer \(retryToken)"
            return try await next(authed, body, baseURL)
        }
        return try await next(request, body, baseURL)
    }
}

/// Localizes the API's `message` (`zh-TW` or `en`).
struct LanguageMiddleware: ClientMiddleware {
    let language: @Sendable () -> Language

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var request = request
        request.headerFields[.acceptLanguage] = language().localeIdentifier
        return try await next(request, body, baseURL)
    }
}

/// One line per request in the debug console (method, path, status, time). Never logs bodies or tokens.
struct LoggingMiddleware: ClientMiddleware {
    private static let logger = Logger(subsystem: "com.vomatt.app", category: "api")

    func intercept(
        _ request: HTTPRequest, body: HTTPBody?, baseURL: URL, operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let start = ContinuousClock.now
        let path = request.path ?? ""
        do {
            let (response, responseBody) = try await next(request, body, baseURL)
            Self.logger.debug("\(request.method.rawValue) \(path) → \(response.status.code) (\(ContinuousClock.now - start))")
            return (response, responseBody)
        } catch {
            Self.logger.debug("\(request.method.rawValue) \(path) failed: \(error.localizedDescription)")
            throw error
        }
    }
}

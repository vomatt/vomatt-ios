import Foundation

/// `rejected`: the backend refused the refresh token, so the session is over
/// (`suspicious` means it saw a used token come back and ended this sign-in).
/// `unavailable`: the backend couldn't be asked; the session may still be fine.
public enum RefreshResult: Equatable, Sendable {
    case ok(AuthTokens)
    case rejected(suspicious: Bool)
    case unavailable
}

public enum SessionEvent: Equatable, Sendable {
    case signedIn(userId: String?)
    /// `expired`: the API ended the session (not the user signing out).
    /// `revoked`: it was signed out from another device, suspended or reused (`auth.session_revoked`).
    case signedOut(expired: Bool, revoked: Bool = false)
}

/// Owns the tokens. The backend rotates the refresh token on every refresh and
/// ends the sign-in when a used one comes back, so refreshes are single-flight:
/// concurrent callers holding the same refresh token share one request, and a
/// rotated pair is saved before anyone uses it.
public actor Session {
    public typealias Refresher = @Sendable (_ refreshToken: String) async -> RefreshResult

    private let store: TokenStore
    private let refresher: Refresher
    private let leeway: TimeInterval
    private var tokens: AuthTokens?
    private var inFlight: (refreshToken: String, task: Task<RefreshResult, Never>)?
    private let continuation: AsyncStream<SessionEvent>.Continuation

    /// Session changes, for the UI. One consumer.
    public nonisolated let events: AsyncStream<SessionEvent>

    public init(store: TokenStore, leeway: TimeInterval = 60, refresher: @escaping Refresher) {
        self.store = store
        self.refresher = refresher
        self.leeway = leeway
        self.tokens = store.load()
        (events, continuation) = AsyncStream.makeStream(of: SessionEvent.self, bufferingPolicy: .bufferingNewest(8))
    }

    public var isSignedIn: Bool { tokens != nil }

    /// The signed-in user's id (the access token's `sub`).
    public var userId: String? { tokens.flatMap { AccessTokenClaims(token: $0.accessToken).subject } }

    public var refreshToken: String? { tokens?.refreshToken }

    public func signIn(_ tokens: AuthTokens) {
        self.tokens = tokens
        store.save(tokens)
        continuation.yield(.signedIn(userId: userId))
    }

    public func signOut(expired: Bool = false, revoked: Bool = false) {
        guard tokens != nil else { return }
        tokens = nil
        inFlight = nil
        store.clear()
        continuation.yield(.signedOut(expired: expired, revoked: revoked))
    }

    /// An access token to send now, refreshed first when it's about to expire. nil when signed out.
    public func accessToken(now: Date = .now) async -> String? {
        guard let current = tokens else { return nil }
        guard AccessTokenClaims(token: current.accessToken).isExpiringSoon(leeway: leeway, now: now) else {
            return current.accessToken
        }
        return await refresh(current)
    }

    /// The stored access token as is, without refreshing. nil when signed out.
    public func currentAccessToken() -> String? { tokens?.accessToken }

    /// The API refused `failedToken` (401). Refreshes unless another request already did;
    /// returns the token to retry with, or nil when the session is over.
    public func accessTokenAfterRejection(of failedToken: String) async -> String? {
        guard let current = tokens else { return nil }
        if current.accessToken != failedToken { return current.accessToken }
        return await refresh(current, failedToken: failedToken)
    }

    private func refresh(_ current: AuthTokens, failedToken: String? = nil) async -> String? {
        let task: Task<RefreshResult, Never>
        if let inFlight, inFlight.refreshToken == current.refreshToken {
            task = inFlight.task
        } else {
            let refresher = self.refresher
            let token = current.refreshToken
            task = Task { await refresher(token) }
            inFlight = (current.refreshToken, task)
        }
        let result = await task.value
        // Only this request's task: after an unavailable result a newer one can carry the same refresh token
        if inFlight?.task == task { inFlight = nil }

        // Signed out while refreshing: the result is not ours to keep
        guard let active = tokens else { return nil }
        // Another caller may already have applied this result
        if active.refreshToken != current.refreshToken { return active.accessToken }

        switch result {
        case let .ok(rotated):
            tokens = rotated
            store.save(rotated)
            return rotated.accessToken
        case .rejected:
            signOut(expired: true)
            return nil
        case .unavailable:
            // Keep the session; a refused token would only fail again
            return failedToken == nil ? current.accessToken : nil
        }
    }
}

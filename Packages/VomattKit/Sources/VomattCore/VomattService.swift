import Foundation
import OpenAPIRuntime
import OpenAPIURLSession
import VomattAPI

/// Every call the app makes to vomatt-api, through the client generated from
/// `openapi.json`. Mirrors vomatt-web's `features/*/service.ts` and
/// `lib/api/services/*`: same endpoints, same rules, domain models out.
/// Failures throw `APIError`.
public final class VomattService: Sendable {
    public let session: Session
    private let client: Client

    /// - Parameters:
    ///   - baseURL: the vomatt-api origin, no path (the contract's paths start with `/api`).
    ///   - transport: URLSession by default; tests pass a stub.
    public init(
        baseURL: URL,
        tokenStore: TokenStore,
        language: @escaping @Sendable () -> Language,
        transport: (any ClientTransport)? = nil,
        logRequests: Bool = false
    ) {
        let transport = transport ?? URLSessionTransport()
        let configuration = Configuration(dateTranscoder: LenientDateTranscoder())
        let logging: [any ClientMiddleware] = logRequests ? [LoggingMiddleware()] : []
        // Refreshing goes through its own client: it must never carry (or refresh) the access token
        let refreshClient = Client(
            serverURL: baseURL, configuration: configuration, transport: transport,
            middlewares: [ErrorEnvelopeMiddleware()] + logging
        )
        let session = Session(store: tokenStore) { refreshToken in
            await Self.refresh(refreshToken, with: refreshClient)
        }
        self.session = session
        self.client = Client(
            serverURL: baseURL, configuration: configuration, transport: transport,
            middlewares: [
                ErrorEnvelopeMiddleware(), UnknownNotificationKindsMiddleware(), LanguageMiddleware(language: language),
                AuthMiddleware(session: session),
            ] + logging
        )
    }

    private static func refresh(_ refreshToken: String, with client: Client) async -> RefreshResult {
        do {
            let output = try await client.refresh(body: .json(.init(refreshToken: refreshToken)))
            return .ok(try AuthTokens(required(output.ok.body.json.data, "refresh.data")))
        } catch {
            guard let error = unwrap(error) as APIError? else { return .unavailable }
            if error.kind == .network || error.isRateLimited || (error.status ?? 0) >= 500 { return .unavailable }
            return .rejected(suspicious: error.errorCode == "auth.suspicious_login")
        }
    }

    /// Runs a generated call, turning transport and decoding failures into `APIError`.
    private func call<T>(_ request: () async throws -> T) async throws -> T {
        do {
            return try await request()
        } catch {
            throw Self.unwrap(error)
        }
    }

    private static func unwrap(_ error: Error) -> APIError {
        if let error = error as? APIError {
            return error.status == 401 ? APIError(.notAuthenticated, errorCode: error.errorCode, message: error.message) : error
        }
        if let error = error as? ClientError {
            return unwrap(error.underlyingError)
        }
        if error is URLError { return APIError(.network, message: error.localizedDescription) }
        if error is DecodingError { return APIError(.decoding, message: "\(error)") }
        // A generated `.ok` accessor on another status, or anything else unexpected
        return APIError(.decoding, message: "\(error)")
    }

    private func page<DTO, Item>(_ dto: (items: [DTO]?, nextCursor: String?)?, _ map: (DTO) throws -> Item) throws -> CursorPage<Item> {
        guard let dto else { return .empty }
        return CursorPage(items: try (dto.items ?? []).map(map), nextCursor: dto.nextCursor)
    }

    // MARK: Auth

    /// Emails a one-time code. The same code signs in an existing account or creates a new one.
    public func requestOtp(email: String) async throws {
        let email = Email.normalize(email)
        try await call { _ = try await client.sendOtp(body: .json(.init(email: email))).ok }
    }

    /// Verifies the code and starts the session. True when this sign-in created the account.
    @discardableResult
    public func verifyOtp(email: String, code: String) async throws -> Bool {
        let (tokens, isNewUser) = try await call {
            let output = try await client.verifyOtp(body: .json(.init(code: code, email: Email.normalize(email))))
            let data = try required(output.ok.body.json.data, "verifyOtp.data")
            return (try AuthTokens(data), data.isNewUser == true)
        }
        await session.signIn(tokens)
        return isNewUser
    }

    /// A fresh one-time challenge for signing in with any passkey on the device (lasts 5 minutes).
    public func passkeySignInChallenge() async throws -> Data {
        try await call {
            let data = try await client.passkeyLoginOptions().ok.body.json.data
            return try required(Data(base64URLEncoded: required(data?.challenge, "passkeyLoginOptions.challenge")), "passkeyLoginOptions.challenge")
        }
    }

    /// Verifies the signed challenge and starts the session, like `verifyOtp`. A passkey only
    /// exists on an account that is already set up, so there is no new-user step.
    public func signIn(with assertion: PasskeyAssertion) async throws {
        let tokens = try await call {
            let output = try await client.passkeyLoginVerify(body: .json(.init(credential: .init(assertion))))
            return try AuthTokens(required(output.ok.body.json.data, "passkeyLoginVerify.data"))
        }
        await session.signIn(tokens)
    }

    /// Revokes the refresh token on the backend, then ends the session here even when the backend can't be reached.
    public func signOut() async {
        if let refreshToken = await session.refreshToken {
            _ = try? await client.logout(body: .json(.init(refreshToken: refreshToken)))
        }
        await session.signOut()
    }

    // MARK: Polls

    public enum ListStatus: String, Sendable { case open, ended }
    public enum ListSort: String, Sendable { case newest, closing, top }

    /// Feed, Explore and Search: Open or Ended Public Polls. `sort` applies to Open Polls only;
    /// `q` is ignored under 2 characters.
    public func polls(
        status: ListStatus = .open, sort: ListSort? = nil, tag: String? = nil, query: String? = nil,
        cursor: String? = nil, limit: Int = 10
    ) async throws -> CursorPage<Poll> {
        let q = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let input = Operations.ListVotes.Input.Query(
            status: status == .ended ? "ended" : nil,
            sort: status == .open ? sort?.rawValue : nil,
            tag: tag,
            q: (q?.count ?? 0) >= searchMinLength ? q : nil,
            cursor: cursor,
            limit: clampedPageSize(limit)
        )
        return try await call {
            let data = try await client.listVotes(query: input).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Poll.init)
        }
    }

    /// The signed-in user's Polls: created, voted in, or invited to. `open`: Scheduled and Open,
    /// closing soonest first. `ended`: latest first. Each carries `unread`.
    public func myPolls(status: ListStatus = .open, cursor: String? = nil, limit: Int = maxPageSize) async throws -> CursorPage<Poll> {
        try await call {
            let data = try await client.getMyVotes(query: .init(
                status: status == .ended ? "ended" : nil, cursor: cursor, limit: clampedPageSize(limit)
            )).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Poll.init)
        }
    }

    /// Every page of `myPolls`, for insights and notifications that need the whole set.
    public func allMyPolls(status: ListStatus) async throws -> [Poll] {
        try await collectPages(maxPages: 10) { try await self.myPolls(status: status, cursor: $0) }.page.items
    }

    /// A user's opened Polls (Open and Ended), most recently opened first.
    public func userPolls(username: String, cursor: String? = nil, limit: Int = 20) async throws -> CursorPage<Poll> {
        try await call {
            let data = try await client.getUserPolls(path: .init(username: username), query: .init(
                cursor: cursor, limit: clampedPageSize(limit)
            )).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Poll.init)
        }
    }

    /// nil when the Poll doesn't exist (or, signed out, is Invite-only).
    public func poll(id: String) async throws -> Poll? {
        do {
            return try await call {
                try await Poll(required(client.getVote(path: .init(voteId: id)).ok.body.json.data, "getVote.data"))
            }
        } catch let error as APIError where error.status == 404 || error.status == 400 {
            return nil
        }
    }

    /// Who sent the Invitation, for a viewer who can't open the Invite-only Poll yet.
    /// nil when the Poll doesn't exist or isn't Invite-only.
    public func inviteOnlyOwner(pollId: String) async throws -> PollOwner? {
        do {
            return try await call {
                try await PollOwner(required(client.getInviteOnlyCreator(path: .init(voteId: pollId)).ok.body.json.data, "creator.data"))
            }
        } catch let error as APIError where error.status == 404 || error.status == 400 {
            return nil
        }
    }

    /// Ended Polls only. A 403 (`isSealed`) means it is still sealed.
    public func results(pollId: String) async throws -> PollResults {
        try await call {
            try await PollResults(required(client.getVoteResults(path: .init(voteId: pollId)).ok.body.json.data, "results.data"))
        }
    }

    /// Who chose what, oldest Ballot first; only as far as Voter Visibility allows.
    public func voters(pollId: String, cursor: String? = nil) async throws -> CursorPage<Voter> {
        try await call {
            let data = try await client.getVoters(path: .init(voteId: pollId), query: .init(
                cursor: cursor, limit: Int32(maxPageSize)
            )).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Voter.init)
        }
    }

    // MARK: Ballot

    /// Casts or replaces the Ballot. Resolves to the Poll, which has already Ended when
    /// this was the last Invitee's Ballot of an Invite-only Poll. `anonymous` nil keeps the
    /// current Ballot's flag, or the account default for a first Ballot.
    public func castBallot(pollId: String, optionId: String, anonymous: Bool? = nil) async throws -> Poll {
        try await retryingWhenBusy {
            try await Poll(required(client.vote(path: .init(voteId: pollId), body: .json(.init(anonymous: anonymous, optionIds: [optionId])))
                .ok.body.json.data, "vote.data"))
        }
    }

    /// The voter is no longer a Participant and won't be notified. Idempotent.
    public func retractBallot(pollId: String) async throws {
        _ = try await retryingWhenBusy { try await client.retract(path: .init(voteId: pollId)).ok }
    }

    /// A busy write (409) recorded nothing; the API asks for one retry.
    private func retryingWhenBusy<T>(_ request: () async throws -> T) async throws -> T {
        do {
            return try await call(request)
        } catch let error as APIError where error.isBusy {
            return try await call(request)
        }
    }

    // MARK: Owner

    public func createPoll(_ input: PollInput) async throws -> Poll {
        try await call {
            try await Poll(required(client.createVote(body: .json(input.request)).created.body.json.data, "createVote.data"))
        }
    }

    /// Owner only, while Scheduled.
    public func updatePoll(id: String, _ input: PollInput) async throws -> Poll {
        try await call {
            try await Poll(required(client.updateVote(path: .init(voteId: id), body: .json(input.request)).ok.body.json.data, "updateVote.data"))
        }
    }

    /// Ends an Open Unlisted or Invite-only Poll now.
    public func closePoll(id: String) async throws {
        _ = try await call { try await client.deactivateVote(path: .init(voteId: id)).ok }
    }

    /// Only while Scheduled or within the delete window (`deletable`).
    public func deletePoll(id: String) async throws {
        _ = try await call { try await client.deleteVote(path: .init(voteId: id)).ok }
    }

    // MARK: Invitees

    public func invitees(pollId: String) async throws -> [Invitee] {
        try await call {
            (try await client.getInvitees(path: .init(voteId: pollId)).ok.body.json.data ?? []).map(Invitee.init)
        }
    }

    /// Ones already invited are ignored. Resolves to the full list.
    public func addInvitees(pollId: String, _ invitees: InviteesInput) async throws -> [Invitee] {
        try await call {
            (try await client.addInvitees(path: .init(voteId: pollId), body: .json(.init(
                emails: invitees.emails, inviteListIds: invitees.groupIds, userIds: invitees.userIds
            ))).ok.body.json.data ?? []).map(Invitee.init)
        }
    }

    /// By user ID or by the email they were added by. Refused once they hold a Ballot.
    public func removeInvitee(pollId: String, _ person: Person) async throws -> [Invitee] {
        try await call {
            let list = if let email = person.email {
                try await client.removeEmailInvitee(path: .init(voteId: pollId), query: .init(email: email)).ok.body.json.data
            } else {
                try await client.removeInvitee(path: .init(voteId: pollId, userId: person.userId ?? "")).ok.body.json.data
            }
            return (list ?? []).map(Invitee.init)
        }
    }

    // MARK: Comments

    public static let commentPageSize = 20

    /// Top-level Comments, newest first.
    public func comments(pollId: String, cursor: String? = nil) async throws -> CursorPage<Comment> {
        try await call {
            let data = try await client.getComments(path: .init(voteId: pollId), query: .init(
                cursor: cursor, limit: Int32(Self.commentPageSize)
            )).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Comment.init)
        }
    }

    /// Replies to one top-level Comment, oldest first. Pass its `repliesNextCursor` to load the rest
    /// without repeating the Replies the list already carries.
    public func replies(pollId: String, commentId: String, cursor: String? = nil) async throws -> CursorPage<Comment> {
        try await call {
            let data = try await client.getReplies(path: .init(voteId: pollId, commentId: commentId), query: .init(
                cursor: cursor, limit: Int32(Self.commentPageSize)
            )).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Comment.init)
        }
    }

    /// A Reply when `parentId` is set (the API files it under the top-level Comment).
    public func postComment(pollId: String, text: String, parentId: String? = nil) async throws -> Comment {
        try await call {
            try await Comment(required(client.createComment(path: .init(voteId: pollId), body: .json(.init(
                parentId: parentId, text: text
            ))).created.body.json.data, "createComment.data"))
        }
    }

    public func updateComment(pollId: String, commentId: String, text: String) async throws -> Comment {
        try await call {
            try await Comment(required(client.updateComment(path: .init(voteId: pollId, commentId: commentId), body: .json(.init(
                text: text
            ))).ok.body.json.data, "updateComment.data"))
        }
    }

    public func deleteComment(pollId: String, commentId: String) async throws {
        _ = try await call { try await client.deleteComment(path: .init(voteId: pollId, commentId: commentId)).ok }
    }

    /// Signed-in only (signed-out shares aren't counted: 401). Idempotent per user and Poll; returns the Poll's `shareCount`.
    @discardableResult
    public func sharePoll(id: String) async throws -> Int {
        try await call {
            let data = try await client.share(path: .init(voteId: id), body: .json(.init(channel: .native))).ok.body.json.data
            return try Int(required(data?.shareCount, "share.shareCount"))
        }
    }

    /// Signed-in only; not your own Comment (`comment.report.self`). Idempotent: a repeat keeps the first report.
    public func reportComment(pollId: String, commentId: String, reason: ReportReason, note: String? = nil) async throws {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await call {
            try await client.reportComment(
                path: .init(voteId: pollId, commentId: commentId),
                body: .json(.init(note: note?.isEmpty == false ? note : nil, reason: reason.request))
            ).ok
        }
    }

    /// Signed-in only; not your own Poll (`vote.report.self`). Idempotent: a repeat keeps the first report.
    public func reportPoll(id: String, reason: ReportReason, note: String? = nil) async throws {
        let note = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await call {
            try await client.report(
                path: .init(voteId: id),
                body: .json(.init(note: note?.isEmpty == false ? note : nil, reason: reason.request))
            ).ok
        }
    }

    /// Signed-in only. Idempotent: saving a saved Poll keeps its first place in the list. Unsaving needs no access to it.
    public func setBookmark(pollId: String, bookmarked: Bool) async throws {
        _ = try await call {
            if bookmarked {
                _ = try await client.bookmark(path: .init(voteId: pollId)).ok
            } else {
                _ = try await client.unbookmark(path: .init(voteId: pollId)).ok
            }
        }
    }

    /// Signed-in only. The viewer's saved Polls in any state, most recently saved first.
    public func bookmarkedPolls(cursor: String? = nil, limit: Int = 10) async throws -> CursorPage<Poll> {
        try await call {
            let data = try await client.getBookmarkedVotes(query: .init(cursor: cursor, limit: clampedPageSize(limit))).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Poll.init)
        }
    }

    public func setLike(pollId: String, commentId: String, liked: Bool) async throws {
        _ = try await call {
            if liked {
                _ = try await client.likeComment(path: .init(voteId: pollId, commentId: commentId)).ok
            } else {
                _ = try await client.unlikeComment(path: .init(voteId: pollId, commentId: commentId)).ok
            }
        }
    }

    // MARK: Groups

    /// The signed-in user's Groups, by name.
    public func groups() async throws -> [UserGroup] {
        try await call { try (try await client.getInviteLists().ok.body.json.data ?? []).map(UserGroup.init) }
    }

    /// At most 50 Groups per owner (`invite_list.max_reached`).
    public func createGroup(name: String) async throws -> UserGroup {
        try await call {
            try await UserGroup(required(client.createInviteList(body: .json(.init(name: name))).created.body.json.data, "createGroup.data"))
        }
    }

    public func renameGroup(id: String, name: String) async throws -> UserGroup {
        try await call {
            try await UserGroup(required(client.renameInviteList(path: .init(inviteListId: id), body: .json(.init(name: name))).ok.body.json.data, "renameGroup.data"))
        }
    }

    /// Polls that invited the Group keep their Invitees.
    public func deleteGroup(id: String) async throws {
        _ = try await call { try await client.deleteInviteList(path: .init(inviteListId: id)).ok }
    }

    public func groupMembers(groupId: String) async throws -> [GroupMember] {
        try await call { (try await client.getMembers(path: .init(inviteListId: groupId)).ok.body.json.data ?? []).map(GroupMember.init) }
    }

    /// Members already in the Group are ignored; at most 100 (`invite_list.members.max`).
    public func addGroupMembers(groupId: String, userIds: [String], emails: [String]) async throws -> [GroupMember] {
        try await call {
            (try await client.addMembers(path: .init(inviteListId: groupId), body: .json(.init(
                emails: emails, userIds: userIds
            ))).ok.body.json.data ?? []).map(GroupMember.init)
        }
    }

    public func removeGroupMember(groupId: String, _ person: Person) async throws -> [GroupMember] {
        try await call {
            let list = if let email = person.email {
                try await client.removeEmailMember(path: .init(inviteListId: groupId), query: .init(email: email)).ok.body.json.data
            } else {
                try await client.removeMember(path: .init(inviteListId: groupId, userId: person.userId ?? "")).ok.body.json.data
            }
            return (list ?? []).map(GroupMember.init)
        }
    }

    // MARK: Users

    public func myProfile() async throws -> MyProfile {
        try await call { try await MyProfile(required(client.getMyProfile().ok.body.json.data, "getMyProfile.data")) }
    }

    /// nil when there is no such user.
    public func userProfile(username: String) async throws -> UserProfile? {
        do {
            return try await call {
                try await UserProfile(required(client.getUserProfile(path: .init(username: username)).ok.body.json.data, "getUserProfile.data"))
            }
        } catch let error as APIError where error.isNotFound {
            return nil
        }
    }

    /// Omitted fields stay as they are; a blank name clears it, a birthday can't be cleared. Errors carry the API's localized message.
    @discardableResult
    public func updateProfile(
        username: String? = nil, displayName: String? = nil, bio: String? = nil, avatarUrl: String? = nil,
        anonymousBallotByDefault: Bool? = nil, firstName: String? = nil, lastName: String? = nil, birthday: String? = nil
    ) async throws -> UserProfile {
        try await call {
            try await UserProfile(required(client.updateMyProfile(body: .json(.init(
                anonymousBallotByDefault: anonymousBallotByDefault, avatarUrl: avatarUrl, bio: bio, birthday: birthday,
                displayName: displayName, firstName: firstName, lastName: lastName, username: username
            ))).ok.body.json.data, "updateMyProfile.data"))
        }
    }

    /// Saves one of the bot cast as the avatar; only a known kind is accepted.
    public func chooseAvatar(kind: String) async throws {
        guard Avatars.isKind(kind) else { throw APIError(.http(400), errorCode: "avatar.unknown", message: "Unknown avatar") }
        try await updateProfile(avatarUrl: Avatars.avatarUrl(for: kind))
    }

    /// Resolves to every visibility setting.
    public func updateVisibility(_ visibility: [String: Bool]) async throws -> [String: Bool] {
        try await call {
            let data = try await client.updateVisibility(body: .json(.init(visibility: .init(additionalProperties: visibility)))).ok.body.json.data
            return (data?.additionalProperties ?? [:]).compactMapValues { $0 }
        }
    }

    /// Signed-in only; a partial, case-insensitive username match.
    public func searchUsers(_ username: String, cursor: String? = nil, limit: Int = 20) async throws -> CursorPage<UserSummary> {
        try await call {
            let data = try await client.searchUsers(query: .init(
                username: username, cursor: cursor, limit: clampedPageSize(limit)
            )).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, UserSummary.init)
        }
    }

    /// Signed-in only. Idempotent. From now on the API leaves their Polls and Comments out of the viewer's lists.
    public func blockUser(id: String) async throws {
        _ = try await call { try await client.blockUser(path: .init(userId: id)).ok }
    }

    /// Signed-in only. Idempotent.
    public func unblockUser(id: String) async throws {
        _ = try await call { try await client.unblockUser(path: .init(userId: id)).ok }
    }

    /// Signed-in only; most recently blocked first.
    public func blockedUsers(cursor: String? = nil, limit: Int = maxPageSize) async throws -> CursorPage<UserSummary> {
        try await call {
            let data = try await client.listBlockedUsers(query: .init(cursor: cursor, limit: clampedPageSize(limit))).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, UserSummary.init)
        }
    }

    /// Every blocked user, following the cursor to the end.
    public func allBlockedUsers() async throws -> [UserSummary] {
        try await collectPages(maxPages: 20) { try await self.blockedUsers(cursor: $0) }.page.items
    }

    /// Signed-in only. Idempotent; 404 for an unknown or suspended user, 400 for yourself. They get a FOLLOWED notification.
    public func followUser(id: String) async throws {
        _ = try await call { try await client.followUser(path: .init(userId: id)).ok }
    }

    /// Signed-in only. Idempotent.
    public func unfollowUser(id: String) async throws {
        _ = try await call { try await client.unfollowUser(path: .init(userId: id)).ok }
    }

    /// Signed-in only; most recently followed first.
    public func followedUsers(cursor: String? = nil, limit: Int = maxPageSize) async throws -> CursorPage<UserSummary> {
        try await call {
            let data = try await client.listFollowedUsers(query: .init(cursor: cursor, limit: clampedPageSize(limit))).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, UserSummary.init)
        }
    }

    /// Signed-in only; who follows `username`, most recently followed first. 404 for an unknown or suspended user.
    public func followers(username: String, cursor: String? = nil, limit: Int = maxPageSize) async throws -> CursorPage<UserSummary> {
        try await call {
            let data = try await client.listFollowers(
                path: .init(username: username), query: .init(cursor: cursor, limit: clampedPageSize(limit))
            ).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, UserSummary.init)
        }
    }

    /// Signed-in only; whom `username` follows, most recently followed first. 404 for an unknown or suspended user.
    public func following(username: String, cursor: String? = nil, limit: Int = maxPageSize) async throws -> CursorPage<UserSummary> {
        try await call {
            let data = try await client.listFollowing(
                path: .init(username: username), query: .init(cursor: cursor, limit: clampedPageSize(limit))
            ).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, UserSummary.init)
        }
    }

    /// Signed-in only; the followers of `username` whom the viewer follows, most recently followed first.
    /// Empty on the viewer's own profile; 404 for an unknown or suspended user.
    public func mutualFollowers(username: String, cursor: String? = nil, limit: Int = maxPageSize) async throws -> CursorPage<UserSummary> {
        try await call {
            let data = try await client.listMutualFollowers(
                path: .init(username: username), query: .init(cursor: cursor, limit: clampedPageSize(limit))
            ).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, UserSummary.init)
        }
    }

    /// Every followed user, following the cursor to the end.
    public func allFollowedUsers() async throws -> [UserSummary] {
        try await collectPages(maxPages: 20) { try await self.followedUsers(cursor: $0) }.page.items
    }

    /// Signed-in only. Open Public Polls by followed people or carrying a followed tag, most recently opened first.
    public func followingPolls(cursor: String? = nil, limit: Int = 10) async throws -> CursorPage<Poll> {
        try await call {
            let data = try await client.getFollowingVotes(query: .init(cursor: cursor, limit: clampedPageSize(limit))).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Poll.init)
        }
    }

    /// Everything stored about the caller as one pretty-printed JSON document (data portability).
    /// The API allows one export per UTC day; a second call is a 429.
    public func exportMyData() async throws -> Data {
        try await call {
            let export = try await required(client.exportMyData().ok.body.json.data, "data")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(export)
        }
    }

    /// Sends product feedback (max 2000 characters). The API allows a few per UTC day; over it is a 429.
    public func sendFeedback(_ content: String) async throws {
        _ = try await call { try await client.createFeedback(body: .json(.init(content: content))).created }
    }

    /// Permanently deletes the signed-in user's account; the backend revokes every session.
    public func deleteMyAccount() async throws {
        let id = try await myProfile().id
        _ = try await retryingWhenBusy { try await client.deleteUser(path: .init(userId: id)).ok }
        await session.signOut()
    }

    // MARK: Passkeys

    /// Creation options for a new passkey on the signed-in account; each call issues a challenge
    /// that lasts 5 minutes and is spent by one `registerPasskey`.
    public func passkeyRegistrationOptions() async throws -> PasskeyRegistrationOptions {
        try await call {
            try await PasskeyRegistrationOptions(required(client.registrationOptions().ok.body.json.data, "registrationOptions.data"))
        }
    }

    /// Stores the new passkey. A failure spends the challenge: retry with new options.
    @discardableResult
    public func registerPasskey(_ registration: PasskeyRegistration, name: String? = nil) async throws -> Passkey {
        try await call {
            try await Passkey(required(client.verifyRegistration(body: .json(.init(credential: .init(registration), name: name)))
                .ok.body.json.data, "verifyRegistration.data"))
        }
    }

    /// The signed-in user's passkeys, oldest first.
    public func passkeys() async throws -> [Passkey] {
        try await call { try (try await client.listMyPasskeys().ok.body.json.data ?? []).map(Passkey.init) }
    }

    /// It stops signing in to the account; the passkey stays on the device until removed there.
    public func deletePasskey(id: String) async throws {
        _ = try await call { try await client.deleteMyPasskey(path: .init(passkeyId: id)).ok }
    }

    // MARK: Devices

    /// Every session that can still refresh, most recently active first.
    public func deviceSessions() async throws -> [DeviceSession] {
        try await call { try (try await client.listMySessions().ok.body.json.data ?? []).map(DeviceSession.init) }
    }

    /// Signs out one session; 404 when it isn't the caller's or is gone. Signing out the
    /// calling session is a sign-out here too.
    public func signOutDevice(id: String) async throws {
        _ = try await call { try await client.revokeMySession(path: .init(sessionId: id)).ok }
    }

    /// Signs out every session but this one.
    public func signOutOtherDevices() async throws {
        _ = try await call { try await client.revokeMyOtherSessions(query: .init(scope: .others)).ok }
    }

    // MARK: Notifications

    /// Unread feed items of the kinds switched on; with `category`, that tab's only.
    public func unreadCount(category: FeedNotification.Category? = nil) async throws -> Int {
        try await call {
            Int(try await client.unreadCount(query: .init(category: category.flatMap { .init(rawValue: $0.apiValue) })).ok.body.json.data?.count ?? 0)
        }
    }

    /// The feed, newest first; with `category`, one tab (pass the same one with every cursor).
    /// Items can vanish or appear behind the cursor: de-duplicate by `id`.
    /// An item that doesn't fit its kind is left out rather than failing the page.
    public func notifications(
        category: FeedNotification.Category? = nil, cursor: String? = nil, limit: Int = 20
    ) async throws -> CursorPage<FeedNotification> {
        try await call {
            let data = try await client.list(
                query: .init(category: category.flatMap { .init(rawValue: $0.apiValue) }, cursor: cursor, limit: clampedPageSize(limit))
            ).ok.body.json.data
            return CursorPage(items: (data?.items ?? []).compactMap { try? FeedNotification($0) }, nextCursor: data?.nextCursor)
        }
    }

    /// Marks one feed item read. Idempotent.
    public func markNotificationRead(id: String) async throws {
        _ = try await call { try await client.markRead(path: .init(id: id)).ok }
    }

    /// The most ids one `markNotificationsRead` call reads.
    public static let markReadMax = 50

    /// Marks several feed items read, a few requests at a time, and returns the ids left unread: those
    /// whose request failed, and any past `markReadMax`. One that is gone (its Comment deleted, the
    /// follow undone) counts as read.
    public func markNotificationsRead(ids: [String]) async -> [String] {
        var unread = Array(ids.dropFirst(Self.markReadMax))
        let taken = Array(ids.prefix(Self.markReadMax))
        for start in stride(from: 0, to: taken.count, by: 5) {
            let chunk = Array(taken[start..<min(start + 5, taken.count)])
            let failed = await withTaskGroup(of: String?.self) { group in
                for id in chunk {
                    group.addTask {
                        do {
                            try await self.markNotificationRead(id: id)
                        } catch let error as APIError where error.errorCode == "notification.not_found" {
                        } catch {
                            return id
                        }
                        return nil
                    }
                }
                return await group.reduce(into: Set<String>()) { if let id = $1 { $0.insert(id) } }
            }
            unread += chunk.filter(failed.contains)
        }
        return unread
    }

    /// Marks the Poll's current notification read through the deprecated Poll-id form of
    /// `markNotificationRead`. Idempotent; nothing to read is ignored.
    public func markNotificationRead(pollId: String) async {
        _ = try? await call { try await client.markRead(path: .init(id: pollId)).ok }
    }

    public func notificationPreferences() async throws -> NotificationPreferences {
        try await call {
            try await NotificationPreferences(required(client.get().ok.body.json.data, "notificationPreferences.data"))
        }
    }

    /// Omitted switches keep their value. Resolves to all six.
    public func updateNotificationPreferences(
        resultsIn: Bool? = nil, invitations: Bool? = nil, comments: Bool? = nil, mentions: Bool? = nil,
        likes: Bool? = nil, closingSoon: Bool? = nil
    ) async throws -> NotificationPreferences {
        try await call {
            try await NotificationPreferences(required(client.update1(body: .json(.init(
                closingSoon: closingSoon, comments: comments, invitations: invitations, likes: likes, mentions: mentions, resultsIn: resultsIn
            ))).ok.body.json.data, "updateNotificationPreferences.data"))
        }
    }

    // MARK: Tags

    /// Signed-in only; the topics the viewer follows, most recently followed first.
    public func followedTags() async throws -> [Tag] {
        try await call { try (try await client.getFollowedTags().ok.body.json.data ?? []).map(Tag.init) }
    }

    /// Signed-in only. Idempotent. A followed topic adds its Open Public Polls to the Following feed.
    public func setTagFollow(tagId: String, following: Bool) async throws {
        _ = try await call {
            if following {
                _ = try await client.followTag(path: .init(tagId: tagId)).ok
            } else {
                _ = try await client.unfollowTag(path: .init(tagId: tagId)).ok
            }
        }
    }

    /// Most-used topics first; empty when the API is down.
    public func popularTags(limit: Int = 12) async -> [Tag] {
        (try? await call {
            let data = try await client.getPopularTags(query: .init(limit: clampedPageSize(limit))).ok.body.json.data
            return try page(data.map { ($0.items, $0.nextCursor) }, Tag.init).items
        }) ?? []
    }
}

/// The shortest search the API accepts (`vote.search.query_too_short` below it).
public let searchMinLength = 2

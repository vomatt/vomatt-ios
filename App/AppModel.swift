import Foundation
import Observation
import SwiftUI
import VomattCore

/// Build settings the app reads from Info.plist (set in Configs/*.xcconfig).
struct AppConfig {
    let apiURL: URL
    let siteURL: URL
    let supportEmail: String
    let logRequests: Bool

    static let current: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        func url(_ key: String) -> URL {
            guard let value = info[key] as? String, let url = URL(string: value), url.host != nil else {
                fatalError("Info.plist \(key) must be an absolute URL (set VOMATT_* in Configs/*.xcconfig), got \(info[key] ?? "nothing")")
            }
            return url
        }
        return AppConfig(
            apiURL: url("VMAPIURL"),
            siteURL: url("VMSiteURL"),
            supportEmail: info["VMSupportEmail"] as? String ?? "",
            logRequests: (info["VMLogRequests"] as? String) == "YES"
        )
    }()

    func pollURL(_ id: String) -> URL { siteURL.appending(path: "poll/\(id)") }
    func profileURL(_ username: String) -> URL { siteURL.appending(path: username) }
}

enum AppTab: Hashable, CaseIterable {
    case home, explore, notifications, account
}

/// Which people a `FollowListView` lists.
enum FollowListKind: Hashable {
    case followers, following
    /// The followers of the user whom the viewer follows too.
    case mutual
}

/// Screens pushed inside a tab.
enum Route: Hashable {
    case poll(String)
    case profile(String)
    case topic(Tag)
    case people(username: String, kind: FollowListKind)
    case settings
    case inviteLists
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var isError = false
}

/// App-wide state: the session, the signed-in user, language, navigation and toasts.
@Observable
final class AppModel {
    let config: AppConfig
    let service: VomattService
    let drafts = DraftStore()
    @ObservationIgnored private let blockList = BlockList()
    /// Lowercased usernames the viewer blocked; their polls and comments are hidden. Signed in, the API
    /// holds the list and filters its answers too; signed out, it lives on this device only.
    private(set) var blocked: [String] = []
    /// Ids of the blocked people the API knows, by lowercased username, to unblock them.
    @ObservationIgnored private var blockedIds: [String: String] = [:]
    /// People the signed-in viewer follows, most recently followed first. Private to the viewer.
    private(set) var following: [UserSummary] = []
    private var followChanges = 0
    private var followQueue: Task<Void, Never>?
    let language: Language
    let t: Localizer
    var dates: DateFormatting { DateFormatting(language: language) }

    private(set) var userId: String?
    private(set) var me: MyProfile?
    private(set) var unreadCount = 0
    /// The unread count as shown on badges, nil when there is nothing unread.
    var unreadBadge: String? { unreadCount > 0 ? formatUnreadCount(unreadCount) : nil }
    /// Bumped on every sign-in and sign-out, so lists reload with the viewer's Ballots.
    private(set) var sessionGeneration = 0

    var selectedTab: AppTab = .home
    var paths: [AppTab: NavigationPath] = Dictionary(uniqueKeysWithValues: AppTab.allCases.map { ($0, NavigationPath()) })

    /// Non-nil while the sign-in sheet is up; runs once the user is signed in.
    var pendingAuth: PendingAuth?
    var creator: CreatorRequest?
    var toast: Toast?
    /// Non-nil while Block asks for confirmation; every Block entry point goes through it.
    var blockRequest: BlockRequest?

    struct BlockRequest: Identifiable {
        let id = UUID()
        let username: String
        let userId: String?
    }

    struct PendingAuth: Identifiable {
        let id = UUID()
        var onSignedIn: (() -> Void)?
    }

    struct CreatorRequest: Identifiable {
        let id = UUID()
        var poll: Poll?
        var draft: PollDraft?
        var onSaved: ((Poll) -> Void)?
    }

    private static let languageKey = "preferred-language"

    init(config: AppConfig = .current, tokenStore: TokenStore = KeychainTokenStore()) {
        #if DEBUG
        // UI tests start signed out
        if ProcessInfo.processInfo.arguments.contains("-reset-session") {
            tokenStore.clear()
            for name in BlockList().usernames() { BlockList().unblock(name) }
        }
        #endif
        // The device language decides; `-preferred-language` (UI tests) overrides it for one launch.
        let argument = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)[Self.languageKey] as? String
        let language = argument.flatMap(Language.init(rawValue:)) ?? Language.preferred()
        self.config = config
        self.language = language
        self.t = Localizer.load(language, bundle: .main)
        self.blocked = blockList.usernames()
        self.service = VomattService(
            baseURL: config.apiURL,
            tokenStore: tokenStore,
            language: { language },
            logRequests: config.logRequests
        )
    }

    var isSignedIn: Bool { userId != nil }

    /// Reads the stored session and follows its changes for the life of the app.
    func start() async {
        userId = await service.session.userId
        if isSignedIn { await refreshAccount() }
        for await event in service.session.events {
            switch event {
            case let .signedIn(id):
                userId = id
                sessionGeneration += 1
                await refreshAccount()
            case let .signedOut(expired):
                userId = nil
                me = nil
                // The account's blocks stay with the account; only those made signed out remain
                for name in blockedIds.keys { blockList.unblock(name) }
                blockedIds = [:]
                blocked = blockList.usernames()
                following = []
                unreadCount = 0
                sessionGeneration += 1
                if expired { showToast(t("login.sessionExpired")) }
            }
        }
    }

    func refreshAccount() async {
        async let profile = try? service.myProfile()
        async let unread = try? service.unreadCount()
        if let profile = await profile { me = profile }
        if let unread = await unread { unreadCount = unread }
        await syncBlocked()
        let changes = followChanges
        // A follow or unfollow made while the fetch was in flight is newer than its snapshot
        if let followed = try? await service.allFollowedUsers(), changes == followChanges { following = followed }
    }

    func refreshUnread() async {
        if isSignedIn, let count = try? await service.unreadCount() { unreadCount = count }
    }

    func updateMe(_ change: (inout MyProfile) -> Void) {
        guard var profile = me else { return }
        change(&profile)
        me = profile
    }

    /// Runs `action` now when signed in; otherwise asks the user to sign in first.
    func requireAuth(_ action: @escaping () -> Void) {
        if isSignedIn { action() } else { pendingAuth = PendingAuth(onSignedIn: action) }
    }

    func signIn() { pendingAuth = PendingAuth() }

    func signOut() async {
        await service.signOut()
        paths[.account] = NavigationPath()
    }

    func openCreator(poll: Poll? = nil, draft: PollDraft? = nil, onSaved: ((Poll) -> Void)? = nil) {
        requireAuth { [weak self] in
            self?.creator = CreatorRequest(poll: poll, draft: draft, onSaved: onSaved)
        }
    }

    func showToast(_ text: String, isError: Bool = false) {
        toast = Toast(text: text, isError: isError)
    }

    /// Tapping the current tab goes back to its root, like UITabBar.
    func select(_ tab: AppTab) {
        if tab == selectedTab { paths[tab] = NavigationPath() } else { selectedTab = tab }
    }

    func push(_ route: Route) {
        paths[selectedTab, default: NavigationPath()].append(route)
    }

    /// `vomatt://poll/<id>`, `https://<site>/poll/<id>` and `https://<site>/<username>`.
    func open(_ url: URL) {
        let parts = url.scheme == "vomatt"
            ? [url.host()].compactMap { $0 } + url.pathComponents.filter { $0 != "/" }
            : url.pathComponents.filter { $0 != "/" }
        guard let first = parts.first else { return }
        if first == "notifications" {
            selectedTab = .notifications
            paths[.notifications] = NavigationPath()
            return
        }
        selectedTab = .home
        paths[.home] = NavigationPath()
        if first == "poll", parts.count > 1 {
            push(.poll(parts[1]))
        } else if parts.count == 1, !Username.reserved.contains(first) {
            push(.profile(first))
        }
    }

    /// Shares a Poll's canonical web link.
    func shareURL(for poll: Poll) -> URL { config.pollURL(poll.id) }

    /// Tells the API a signed-in user opened the share sheet for a Poll (signed-out shares aren't counted).
    /// `ShareLink` reports no completion, so this counts the tap, not the delivery.
    func recordShare(of poll: Poll) {
        guard isSignedIn else { return }
        Task { try? await service.sharePoll(id: poll.id) }
    }

    // MARK: Poll cache

    /// The newest copy of each Poll a screen changed (a Ballot, an edit), so every
    /// list showing it agrees without refetching.
    private(set) var latestPolls: [String: Poll] = [:]
    private(set) var deletedPollIds: Set<String> = []

    func latest(_ poll: Poll) -> Poll { latestPolls[poll.id] ?? poll }

    func didUpdate(_ poll: Poll) { latestPolls[poll.id] = poll }

    func didDelete(_ pollId: String) {
        deletedPollIds.insert(pollId)
        latestPolls[pollId] = nil
    }

    /// Lists drop Polls deleted elsewhere or by blocked people, and show the newest copy of the rest.
    func visible(_ polls: [Poll]) -> [Poll] {
        polls.filter { !deletedPollIds.contains($0.id) && !isBlocked($0.creatorUsername) }.map(latest)
    }

    // MARK: Following

    func isFollowing(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return following.contains { $0.id == userId }
    }

    /// Shows the change at once and tells the API; the change is undone when the call fails.
    func follow(_ user: UserSummary) {
        guard isSignedIn, !isFollowing(user.id) else { return }
        following.insert(user, at: 0)
        followChanges += 1
        enqueueFollow { [self] in
            do {
                try await service.followUser(id: user.id)
            } catch {
                following.removeAll { $0.id == user.id }
                showToast(t.message(for: error, fallback: "ios.followFailed"), isError: true)
            }
        }
    }

    /// Follow calls run one after another, so a quick toggle reaches the API in the order it was made.
    private func enqueueFollow(_ call: @escaping () async -> Void) {
        let previous = followQueue
        followQueue = Task {
            await previous?.value
            await call()
        }
    }

    func unfollow(_ userId: String) {
        guard let index = following.firstIndex(where: { $0.id == userId }) else { return }
        let user = following.remove(at: index)
        followChanges += 1
        enqueueFollow { [self] in
            do {
                try await service.unfollowUser(id: userId)
            } catch {
                if !isFollowing(userId) { following.insert(user, at: min(index, following.count)) }
                showToast(t.message(for: error, fallback: "ios.unfollowFailed"), isError: true)
            }
        }
    }

    // MARK: Blocking

    func isBlocked(_ username: String?) -> Bool {
        guard let username else { return false }
        return blocked.contains(username.lowercased())
    }

    /// Hides the person at once; signed in, the API is told too and the block is undone when it fails.
    func block(_ username: String, userId id: String?) {
        blocked = blockList.block(username)
        showToast(t("ios.blockedToast", ["name": username]))
        guard isSignedIn, let id else { return }
        // The API unfollows whoever is blocked
        let unfollowed = following.first { $0.id == id }
        if unfollowed != nil { following.removeAll { $0.id == id }; followChanges += 1 }
        let key = username.lowercased()
        // Recorded before the call so a quick unblock reaches the API too
        let wasBlocked = blockedIds[key] != nil
        blockedIds[key] = id
        // Queued behind follow calls, so a follow made just before cannot reach the API after the block
        enqueueFollow { [self] in
            do {
                try await service.blockUser(id: id)
            } catch {
                if !wasBlocked {
                    blockedIds[key] = nil
                    blocked = blockList.unblock(username)
                }
                if let unfollowed, !isFollowing(id) { following.insert(unfollowed, at: 0); followChanges += 1 }
                showToast(t.message(for: error, fallback: "ios.blockFailed"), isError: true)
            }
        }
    }

    func unblock(_ username: String) {
        let key = username.lowercased()
        blocked = blockList.unblock(username)
        guard isSignedIn, let id = blockedIds[key] else { return }
        blockedIds[key] = nil
        Task {
            do {
                try await service.unblockUser(id: id)
            } catch {
                blocked = blockList.block(username)
                blockedIds[key] = id
                showToast(t.message(for: error, fallback: "ios.unblockFailed"), isError: true)
            }
        }
    }

    /// Takes the API's list as the truth once signed in. People blocked on this device while signed
    /// out are sent up first, so nothing comes back into view.
    func syncBlocked() async {
        guard isSignedIn, let remote = try? await service.allBlockedUsers() else { return }
        let known = Set(remote.map { $0.username.lowercased() })
        // Synced before but gone from the API: unblocked on another device
        for name in blockedIds.keys where !known.contains(name) {
            blockedIds[name] = nil
            blockList.unblock(name)
        }
        for name in blockList.usernames() where !known.contains(name) && blockedIds[name] == nil {
            let match = try? await service.searchUsers(name).items.first { $0.username.lowercased() == name }
            if let id = match?.id, (try? await service.blockUser(id: id)) != nil { blockedIds[name] = id }
        }
        for user in remote {
            blockedIds[user.username.lowercased()] = user.id
            blockList.block(user.username)
        }
        blocked = blockList.usernames()
    }
}

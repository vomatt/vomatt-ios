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
    case home, explore, myPolls, account
}

/// Screens pushed inside a tab.
enum Route: Hashable {
    case poll(String)
    case profile(String)
    case topic(Tag)
    case notifications
}

struct Toast: Equatable, Identifiable {
    let id = UUID()
    var text: String
    var isError = false
}

/// The language the API should localize into, readable from the networking layer's threads.
nonisolated final class LanguageBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Language
    init(_ value: Language) { self.value = value }
    var current: Language {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
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
    @ObservationIgnored private let languageBox: LanguageBox

    var language: Language {
        didSet {
            languageBox.current = language
            t = Localizer.load(language, bundle: .main)
            UserDefaults.standard.set(language.rawValue, forKey: Self.languageKey)
        }
    }
    private(set) var t: Localizer
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
        let stored = UserDefaults.standard.string(forKey: Self.languageKey).flatMap(Language.init(rawValue:))
        let language = stored ?? Language.preferred()
        let box = LanguageBox(language)
        self.config = config
        self.languageBox = box
        self.language = language
        self.t = Localizer.load(language, bundle: .main)
        self.blocked = blockList.usernames()
        self.service = VomattService(
            baseURL: config.apiURL,
            tokenStore: tokenStore,
            language: { box.current },
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
        selectedTab = .home
        paths[.home] = NavigationPath()
        if first == "poll", parts.count > 1 {
            push(.poll(parts[1]))
        } else if first == "notifications" {
            selectedTab = .myPolls
            push(.notifications)
        } else if parts.count == 1, !Username.reserved.contains(first) {
            push(.profile(first))
        }
    }

    /// Shares a Poll's canonical web link.
    func shareURL(for poll: Poll) -> URL { config.pollURL(poll.id) }

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
        Task {
            do {
                try await service.blockUser(id: id)
                blockedIds[username.lowercased()] = id
            } catch {
                blocked = blockList.unblock(username)
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
        for name in blockList.usernames() where !known.contains(name) {
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

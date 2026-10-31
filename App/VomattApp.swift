import SwiftUI
import VomattCore

@main
struct VomattApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(\.locale, Locale(identifier: app.language.localeIdentifier))
                .tint(Tokens.foreground)
                .task { await app.start() }
                .onOpenURL { app.open($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { app.open(url) }
                }
        }
    }
}

/// The four tabs plus the create action, like the web's mobile `TabBar`: Home, Explore, Create,
/// Notifications, Profile.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// The tab bar steps aside while typing, like UITabBar
    @State private var isKeyboardVisible = false
    @AppStorage(ThemeChoice.storageKey) private var theme = ThemeChoice.system

    var body: some View {
        @Bindable var app = app
        tabs
        .toastHost(app)
        .preferredColorScheme(theme.colorScheme)
        .sheet(item: $app.pendingAuth) { pending in
            AuthSheet(onSignedIn: pending.onSignedIn)
        }
        .fullScreenCover(item: $app.creator) { request in
            PollCreatorView(request: request)
        }
        .alert(
            app.t("blocks.confirmTitle", ["username": app.blockRequest?.username ?? ""]),
            isPresented: Binding(get: { app.blockRequest != nil }, set: { if !$0 { app.blockRequest = nil } }),
            presenting: app.blockRequest
        ) { request in
            Button(app.t("blocks.block"), role: .destructive) { app.block(request.username, userId: request.userId) }
            Button(app.t("common.cancel"), role: .cancel) {}
        } message: { _ in
            Text(app.t("blocks.confirmBody"))
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.refreshUnread() } }
        }
    }

    @ViewBuilder private var tabs: some View {
        if #available(iOS 26, *) { systemTabs } else { flatTabs }
    }

    /// iOS 26+: the system tab bar, floating in Liquid Glass (README, "Liquid Glass").
    /// Create is a tab that opens the creator instead of being selected.
    @available(iOS 26, *)
    private var systemTabs: some View {
        TabView(selection: Binding<SystemTab>(
            get: { .app(app.selectedTab) },
            set: { selection in
                switch selection {
                case .create: app.openCreator()
                case let .app(tab): app.select(tab)
                }
            }
        )) {
            Tab(app.t(AppTab.home.titleKey), systemImage: AppTab.home.icon, value: SystemTab.app(.home)) {
                tab(.home) { HomeView() }
            }
            Tab(app.t(AppTab.explore.titleKey), systemImage: AppTab.explore.icon, value: SystemTab.app(.explore)) {
                tab(.explore) { ExploreView() }
            }
            Tab(app.t("ios.create"), systemImage: "plus.square.fill", value: SystemTab.create) {
                Color.clear
            }
            .accessibilityLabel(app.t("common.createPoll"))
            Tab(app.t(AppTab.notifications.titleKey), systemImage: AppTab.notifications.icon, value: SystemTab.app(.notifications)) {
                tab(.notifications) { NotificationsView() }
            }
            .badge(app.unreadBadge.map(Text.init))
            Tab(app.t(AppTab.account.titleKey), systemImage: AppTab.account.icon, value: SystemTab.app(.account)) {
                tab(.account) { AccountTab() }
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }

    /// iOS 17–25: the web's flat `TabBar`.
    private var flatTabs: some View {
        @Bindable var app = app
        return TabView(selection: $app.selectedTab) {
            tab(.home) { HomeView() }.tag(AppTab.home)
            tab(.explore) { ExploreView() }.tag(AppTab.explore)
            tab(.notifications) { NotificationsView() }.tag(AppTab.notifications)
            tab(.account) { AccountTab() }.tag(AppTab.account)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isKeyboardVisible { VMTabBar() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
    }

    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        @Bindable var app = app
        return NavigationStack(path: Binding(
            get: { app.paths[tab] ?? NavigationPath() },
            set: { app.paths[tab] = $0 }
        )) {
            content()
                .navigationDestination(for: Route.self) { RouteView(route: $0) }
        }
    }
}

/// Shared by the system tab bar (iOS 26+) and `VMTabBar`.
private extension AppTab {
    var titleKey: String {
        switch self {
        case .home: "navigation.home"
        case .explore: "common.explore"
        case .notifications: "common.notifications"
        case .account: "navigation.profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .explore: "magnifyingglass"
        case .notifications: "bell"
        case .account: "person.crop.circle"
        }
    }

    var activeIcon: String { self == .explore ? icon : icon + ".fill" }
}

private enum SystemTab: Hashable {
    case app(AppTab)
    case create
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case let .poll(id): PollDetailView(pollId: id)
        case let .profile(username): ProfileView(username: username)
        case let .topic(tag): FeedView(tag: tag)
        case let .people(username, kind): FollowListView(username: username, kind: kind)
        case .settings: SettingsView()
        case .inviteLists: InviteListsView()
        }
    }
}

/// `bg-card border-t`, 64pt plus the safe area; the active tab gets an ink underline,
/// the center is the ink-square create action.
struct VMTabBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            item(.home)
            item(.explore)
            Button { app.openCreator() } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    .frame(width: 52)
            }
            .buttonStyle(.vm(.default, size: .icon))
            .frame(maxWidth: .infinity)
            .accessibilityLabel(app.t("common.createPoll"))
            item(.notifications, badge: app.unreadBadge)
            item(.account)
        }
        .frame(height: 64)
        .background(Tokens.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
    }

    private func item(_ tab: AppTab, badge: String? = nil) -> some View {
        let isActive = app.selectedTab == tab
        return Button { app.select(tab) } label: {
            Image(systemName: isActive ? tab.activeIcon : tab.icon)
                .font(.system(size: 22, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Tokens.foreground : Tokens.mutedForeground)
                .frame(width: 48, height: 48)
                .overlay(alignment: .bottom) {
                    if isActive { Rectangle().fill(Tokens.foreground).frame(height: 2) }
                }
                // The web's tab: an Alert dot on the bell, the count read out by VoiceOver
                .overlay(alignment: .topTrailing) {
                    if badge != nil { UnreadDot(label: "").offset(x: -10, y: 10).accessibilityHidden(true) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.t(tab.titleKey))
        .accessibilityValue(badge.map { "\($0) \(app.t("notifications.unread"))" } ?? "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

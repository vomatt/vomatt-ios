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

/// The four tabs plus the create action, like the web's mobile `TabBar`.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    /// The tab bar steps aside while typing, like UITabBar
    @State private var isKeyboardVisible = false

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            tab(.home) { HomeView() }
            tab(.explore) { ExploreView() }
            tab(.myPolls) { MyPollsView() }
            tab(.account) { AccountTab() }
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
        .toastHost(app)
        .sheet(item: $app.pendingAuth) { pending in
            AuthSheet(onSignedIn: pending.onSignedIn)
        }
        .fullScreenCover(item: $app.creator) { request in
            PollCreatorView(request: request)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.refreshUnread() } }
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
        .tag(tab)
    }
}

struct RouteView: View {
    let route: Route
    var body: some View {
        switch route {
        case let .poll(id): PollDetailView(pollId: id)
        case let .profile(username): ProfileView(username: username)
        case let .topic(tag): FeedView(tag: tag)
        case .notifications: NotificationsView()
        }
    }
}

/// `bg-card border-t`, 64pt plus the safe area; the active tab gets an ink underline,
/// the center is the ink-square create action.
struct VMTabBar: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 0) {
            item(.home, icon: "house", activeIcon: "house.fill", label: app.t("navigation.home"))
            item(.explore, icon: "magnifyingglass", activeIcon: "magnifyingglass", label: app.t("common.explore"))
            Button { app.openCreator() } label: {
                Image(systemName: "plus").font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Tokens.primaryForeground)
                    .frame(width: 52, height: 44)
                    .background(Tokens.primary, in: RoundedRectangle(cornerRadius: Radius.lg))
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(app.t("common.createPoll"))
            item(.myPolls, icon: "star", activeIcon: "star.fill", label: app.t("common.myPolls"), badge: app.unreadCount)
            item(.account, icon: "person.crop.circle", activeIcon: "person.crop.circle.fill", label: app.t("navigation.profile"))
        }
        .frame(height: 64)
        .background(Tokens.card.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
    }

    private func item(_ tab: AppTab, icon: String, activeIcon: String, label: String, badge: Int = 0) -> some View {
        let isActive = app.selectedTab == tab
        return Button {
            if isActive {
                // Tapping the current tab goes back to its root, like UITabBar
                app.paths[tab] = NavigationPath()
            } else {
                app.selectedTab = tab
            }
        } label: {
            Image(systemName: isActive ? activeIcon : icon)
                .font(.system(size: 22, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? Tokens.foreground : Tokens.mutedForeground)
                .frame(width: 48, height: 48)
                .overlay(alignment: .bottom) {
                    if isActive { Rectangle().fill(Tokens.foreground).frame(height: 2) }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 { UnreadDot(label: "\(badge)").offset(x: -6, y: 8) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(badge > 0 ? "\(badge) \(app.t("notifications.unread"))" : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

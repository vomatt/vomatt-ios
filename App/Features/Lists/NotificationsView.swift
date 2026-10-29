import SwiftUI
import VomattCore

/// The notification feed, newest first: results, invitations, new followers, comments and replies,
/// and (if switched on) Polls about to close. Opening an item reads it.
struct NotificationsView: View {
    @Environment(AppModel.self) private var app
    @State private var list: CursorList<FeedNotification>?
    /// The tab; nil is every category.
    @State private var category: FeedNotification.Category?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.t("notifications.title")).displayHeading(32).accessibilityAddTraits(.isHeader)
                    Text(app.t("ios.notificationsIntro")).font(.vmBody).foregroundStyle(Tokens.mutedForeground)
                }
                LineTabs(
                    items: [(nil, app.t("ios.notifTabAll"))] + FeedNotification.Category.allCases.map { ($0, tabLabel($0)) },
                    selection: $category
                )
                content
            }
            .pageColumn()
            .padding(.vertical, 24)
        }
        .refreshable { await load() }
        .canvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if app.unreadCount > 0 || list?.items.contains(where: { !$0.read }) == true {
                    Button(app.t("ios.markAllRead")) { Task { await markAllRead() } }
                }
            }
        }
        .task(id: TabKey(generation: app.sessionGeneration, category: category)) { await load() }
    }

    private struct TabKey: Equatable {
        var generation: Int
        var category: FeedNotification.Category?
    }

    private func tabLabel(_ category: FeedNotification.Category) -> String {
        switch category {
        case .conversation: app.t("ios.notifTabConversation")
        case .like: app.t("ios.notifTabLikes")
        case .pollEnd: app.t("ios.notifTabPolls")
        case .invitation: app.t("ios.notifTabInvitations")
        case .follow: app.t("ios.notifTabFollows")
        }
    }

    @ViewBuilder private var content: some View {
        if let list {
            switch list.phase {
            case .idle, .loading:
                VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 72, radius: Radius.xl) } }
            case .failed:
                LoadFailed(message: app.t("notifications.loadFailed")) { await load() }
            case .loaded:
                if list.items.isEmpty {
                    EmptyState {
                        Image(systemName: "bell").font(.system(size: 20)).foregroundStyle(Tokens.foreground)
                            .frame(width: 44, height: 44).background(Tokens.secondary, in: Circle())
                        Text(app.t("notifications.empty"))
                    }
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(list.items) { item in
                            NotificationRow(item: item) { open(item) }
                        }
                    }
                    LoadMoreFooter(list: list)
                }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
        }
    }

    private func load() async {
        guard app.isSignedIn else { return }
        let service = app.service
        let category = category
        // A tab switch starts a fresh list: a cursor belongs to one category
        let list = CursorList { try await service.notifications(category: category, cursor: $0) }
        self.list = list
        await list.reload()
        await app.refreshUnread()
    }

    private func open(_ item: FeedNotification) {
        Task { await markRead(item) }
        if item.kind == .followed, let actor = item.actor {
            app.push(.profile(actor.username))
        } else if let poll = item.poll {
            app.push(.poll(poll.id))
        }
    }

    /// Clears the dot at once; a gone item (`notification.not_found`) has nothing left to read.
    private func markRead(_ item: FeedNotification) async {
        guard !item.read else { return }
        setRead { $0.id == item.id }
        try? await app.service.markNotificationRead(id: item.id)
        await app.refreshUnread()
    }

    private func markAllRead() async {
        do {
            try await app.service.markAllNotificationsRead()
            setRead { _ in true }
            await app.refreshUnread()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "ios.markAllReadFailed"), isError: true)
        }
    }

    private func setRead(where matches: (FeedNotification) -> Bool) {
        list?.update { items in
            items = items.map { item in
                var item = item
                if matches(item) { item.read = true }
                return item
            }
        }
    }
}

/// One feed item: who or what, a sentence, a detail line, when; an unread dot while unread.
private struct NotificationRow: View {
    @Environment(AppModel.self) private var app
    let item: FeedNotification
    let open: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: open) {
                HStack(alignment: .top, spacing: 12) {
                    leading
                    VStack(alignment: .leading, spacing: 4) {
                        Text(headline).font(.vm(15, item.read ? .regular : .medium)).foregroundStyle(Tokens.foreground)
                            .multilineTextAlignment(.leading)
                        if let detail {
                            Text(detail).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                        Text(app.dates.fromNow(item.createdAt)).font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !item.read { UnreadDot(label: app.t("notifications.unread")).padding(.top, 6) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if item.kind == .followed, let actor = item.actor { PersonFollowButton(user: actor) }
        }
        .card()
    }

    @ViewBuilder private var leading: some View {
        if let actor = item.actor {
            AvatarView(username: actor.username, avatarUrl: actor.avatarUrl, size: 36)
        } else {
            Image(systemName: item.kind == .result ? "chart.bar" : "bell").font(.system(size: 16))
                .foregroundStyle(Tokens.foreground)
                .frame(width: 36, height: 36).background(Tokens.secondary, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var headline: String {
        let name = item.actor?.username ?? ""
        let title = item.poll?.title ?? ""
        return switch item.kind {
        case .result: app.t("ios.notifResult", ["title": title])
        case .cancelled: app.t("ios.notifCancelled", ["title": title])
        case .invitation: app.t("ios.notifInvitation", ["name": name, "title": title])
        case .followed: app.t("ios.notifFollowed", ["name": name])
        case .comment: app.t(item.comment?.parentId == nil ? "ios.notifCommented" : "ios.notifReplied", ["name": name, "title": title])
        case .mention: app.t("ios.notifMentioned", ["name": name, "title": title])
        case .like: app.t(item.comment?.parentId == nil ? "ios.notifLikedComment" : "ios.notifLikedReply", ["name": name, "title": title])
        case .closingSoon: app.t("ios.notifClosingSoon", ["title": title])
        }
    }

    /// Never a live count while a Poll is open: Turnout only, and the outcome once it Ended.
    private var detail: String? {
        switch item.kind {
        case .comment, .mention, .like:
            return item.comment?.excerpt
        case .closingSoon:
            return item.poll.map { app.t("poll.voted", ["count": app.t.number($0.turnout)]) }
        case .result:
            guard let poll = item.poll, poll.isEnded else { return nil }
            return outcome(poll)
        case .cancelled, .invitation, .followed:
            return nil
        }
    }

    private func outcome(_ poll: FeedNotification.PollInfo) -> String {
        guard let labels = poll.winningOptionLabels, !labels.isEmpty else { return app.t("ios.notifNoWinner") }
        let winners = app.t(poll.tie == true ? "ios.notifTie" : "ios.notifWinner", ["labels": labels.joined(separator: ", ")])
        guard let won = poll.viewerWon else { return winners }
        return winners + " · " + app.t(won ? "ios.notifYourChoiceWon" : "ios.notifYourChoiceLost")
    }
}

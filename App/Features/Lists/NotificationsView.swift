import SwiftUI
import VomattCore

/// The Notifications tab, from the web's `NotificationList`: newest first, grouped by day, each run of
/// follows as one row, with a pill per category. Results rows stay until opened, so a sealed promise is
/// never lost in the list. Opening a row reads it.
struct NotificationsView: View {
    @Environment(AppModel.self) private var app
    @State private var list: CursorList<FeedNotification>?
    /// The tab `list` holds; nil is every category.
    @State private var category: FeedNotification.Category?
    @State private var isSwitching = false
    @State private var isMarking = false

    var body: some View {
        Group {
            if app.isSignedIn {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        content
                    }
                    .pageColumn()
                    .padding(.vertical, 24)
                }
                .refreshable { await load() }
                .task(id: app.sessionGeneration) { await load() }
            } else {
                SignedOutPlaceholder(title: app.t("notifications.title"))
            }
        }
        .canvas()
        .navigationBarTitleDisplayMode(.inline)
    }

    private var unread: [FeedNotification] { list?.items.filter { !$0.read } ?? [] }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(app.t("notifications.title")).displayHeading(32).accessibilityAddTraits(.isHeader)
                Text(app.t("notifications.intro")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if list?.phase == .loaded, !isEmpty {
                Button(app.t("notifications.markAllRead")) { Task { await markAllRead() } }
                    .buttonStyle(.vm(.outline, size: .sm))
                    // Unread ones may sit past the loaded pages; read-all reaches them too
                    .disabled(isMarking || (unread.isEmpty && app.unreadCount == 0))
            }
        }
    }

    /// Nothing at all: unknown kinds are left out, so an empty page can still have more after it.
    private var isEmpty: Bool {
        guard let list else { return false }
        return category == nil && list.items.isEmpty && !list.hasMore && app.unreadCount == 0
    }

    @ViewBuilder private var content: some View {
        if let list {
            switch list.phase {
            case .idle, .loading:
                VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 64, radius: Radius.xl) } }
            case .failed:
                LoadFailed(message: app.t("notifications.loadFailed")) { await load() }
            case .loaded:
                if isEmpty {
                    EmptyState {
                        Image(systemName: "bell").font(.system(size: 20)).foregroundStyle(Tokens.foreground)
                            .frame(width: 44, height: 44).background(Tokens.secondary, in: Circle())
                            .accessibilityHidden(true)
                        Text(app.t("notifications.empty")).font(.vm(16, .medium)).foregroundStyle(Tokens.foreground)
                            .accessibilityAddTraits(.isHeader)
                        Text(app.t("notifications.emptyHint"))
                    }
                } else {
                    feed(list)
                }
            }
        } else {
            VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 64, radius: Radius.xl) } }
        }
    }

    private func feed(_ list: CursorList<FeedNotification>) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                FilterPills(
                    label: app.t("ios.notifCategoryLabel"),
                    selection: Binding(get: { category }, set: { next in Task { await changeCategory(next) } }),
                    options: [(nil, app.t("profile.filterAll"), nil)] + FeedNotification.Category.allCases.map { ($0, categoryLabel($0), nil) }
                )
            }
            if list.items.isEmpty {
                EmptyState { Text(app.t("ios.notifCategoryEmpty")) }
            }
            ForEach(ActivitySection.sections(list.items)) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(app.t("notifications.day.\(section.day.rawValue)"))
                        .font(.vm(12, .medium, relativeTo: .caption)).foregroundStyle(Tokens.mutedForeground)
                        .padding(.horizontal, 2)
                        .accessibilityAddTraits(.isHeader)
                    LazyVStack(spacing: 8) {
                        ForEach(section.entries) { entry in
                            NotificationRow(entry: entry) { read(entry) }
                        }
                    }
                }
            }
            LoadMoreFooter(list: list)
        }
    }

    private func categoryLabel(_ category: FeedNotification.Category) -> String {
        switch category {
        case .conversation: app.t("ios.notifTabConversation")
        case .like: app.t("ios.notifTabLikes")
        case .pollEnd: app.t("ios.notifTabPolls")
        case .invitation: app.t("ios.notifTabInvitations")
        case .follow: app.t("ios.notifTabFollows")
        }
    }

    /// Refresh and retry keep the tab: the list pages with the category it was made for.
    private func load() async {
        guard app.isSignedIn else { return }
        let list = list ?? makeList(nil)
        self.list = list
        async let unread: Void = app.refreshUnread()
        await list.reload()
        await unread
    }

    private func makeList(_ category: FeedNotification.Category?) -> CursorList<FeedNotification> {
        let service = app.service
        return CursorList { try await service.notifications(category: category, cursor: $0) }
    }

    /// A tab's first page loads before the tab shows; when it fails, the current tab stays.
    private func changeCategory(_ next: FeedNotification.Category?) async {
        // A Load more in flight would append the old tab's page after the switch
        guard next != category, !isSwitching, list?.isLoadingMore != true else { return }
        isSwitching = true
        defer { isSwitching = false }
        let fresh = makeList(next)
        await fresh.reload()
        guard fresh.phase == .loaded else {
            return app.showToast(app.t("ios.notifCategoryFailed"), isError: true)
        }
        list = fresh
        category = next
    }

    /// The dot clears at once; a failed request leaves it unread on the server, so the next visit shows it again.
    private func read(_ entry: ActivityEntry) {
        let ids = Set(entry.items.filter { !$0.read }.map(\.id))
        guard !ids.isEmpty else { return }
        setRead { ids.contains($0.id) }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for id in ids { group.addTask { try? await app.service.markNotificationRead(id: id) } }
            }
            await app.refreshUnread()
        }
    }

    private func markAllRead() async {
        isMarking = true
        defer { isMarking = false }
        do {
            try await app.service.markAllNotificationsRead()
            setRead { _ in true }
            await app.refreshUnread()
        } catch {
            app.showToast(app.t("notifications.markAllFailed"), isError: true)
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

/// One row, from the web's `NotificationRows`: unread rows are a card with an Alert dot after the line,
/// read ones sit flat; an unread result is Tide, the promise kept. Tapping the row opens what it is about.
private struct NotificationRow: View {
    @Environment(AppModel.self) private var app
    let entry: ActivityEntry
    /// Marks the entry read: the person opened it or acted on it.
    let read: () -> Void

    private var item: FeedNotification { entry.items[0] }
    private var unread: Bool { entry.isUnread }
    private var tide: Bool { item.kind == .result && unread }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: open) {
                HStack(alignment: .center, spacing: 14) {
                    icon
                    VStack(alignment: .leading, spacing: 2) {
                        lineWithDot
                            .font(.vm(15))
                            .foregroundStyle(item.kind == .cancelled ? Tokens.mutedForeground : Tokens.foreground)
                            .multilineTextAlignment(.leading)
                        Text(meta.joined(separator: " · "))
                            .font(.vm(12, relativeTo: .caption))
                            .foregroundStyle(tide ? Tokens.tideForeground : Tokens.mutedForeground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            action
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(unread ? (tide ? Tokens.tideTint : Tokens.card) : .clear, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay {
            if unread {
                RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(tide ? Tokens.tideLine : Tokens.border, lineWidth: 1)
            }
        }
    }

    private func open() {
        read()
        switch entry {
        case .follows:
            if let me = app.me { app.push(.people(username: me.username, kind: .followers)) }
        case let .single(item):
            if item.kind == .followed, let actor = item.actor {
                app.push(.profile(actor.username))
            } else if let poll = item.poll {
                app.push(.poll(poll.id))
            }
        }
    }

    // MARK: Icon

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .result:
            SealMark(size: 36)
        case .cancelled:
            disc("nosign")
        case .closingSoon:
            disc("clock", tint: Tokens.foreground)
        case .invitation, .followed, .comment, .mention, .like:
            if let actor = item.actor {
                AvatarView(username: actor.username, avatarUrl: actor.avatarUrl, size: 36).accessibilityHidden(true)
            } else {
                disc("bell")
            }
        }
    }

    private func disc(_ symbol: String, tint: Color = Tokens.mutedForeground) -> some View {
        Image(systemName: symbol).font(.system(size: 15))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36).background(Tokens.secondary, in: Circle())
            .accessibilityHidden(true)
    }

    // MARK: Line

    /// The line, with the dot after its last word while unread.
    @ViewBuilder private var lineWithDot: some View {
        if unread {
            // The dot rides the text's last line, like the web's word joiner
            (line + Text("  ") + Text(Image(systemName: "circle.fill")).font(.system(size: 8)).foregroundStyle(Tokens.alert).baselineOffset(2))
                .accessibilityLabel(Text(lineAccessibility) + Text(", ") + Text(app.t("notifications.unread")))
        } else {
            line
        }
    }

    private var actorName: String { "@\(item.actor?.username ?? "")" }
    private var title: String { item.poll?.title ?? "" }

    private enum Emphasis { case plain, strong, titled }

    private struct Part {
        let text: String
        var emphasis = Emphasis.plain
    }

    /// The row's words, written once for both the styled line and VoiceOver: a localized template, what fills
    /// each `{name}`, and an optional tail after " · ".
    private struct Wording {
        let template: String
        let parts: [String: Part]
        var tail: Part?
    }

    private var wording: Wording {
        switch entry {
        case let .follows(items):
            return Wording(template: app.t.count("notifications.followedYouGroup", items.count - 1, ["name": "{name}"]),
                           parts: ["name": Part(text: actorName, emphasis: .strong)])
        case .single:
            switch item.kind {
            case .result:
                return Wording(template: "{ended}", parts: ["ended": Part(text: app.t("notifications.ended"), emphasis: unread ? .strong : .plain)],
                               tail: Part(text: title))
            case .cancelled:
                return Wording(template: app.t("notifications.cancelledBy"),
                               parts: ["title": Part(text: title, emphasis: .titled), "name": Part(text: actorName)])
            case .invitation:
                return Wording(template: app.t("notifications.invitedYou"), parts: ["name": Part(text: actorName, emphasis: .strong)],
                               tail: Part(text: title, emphasis: .titled))
            case .followed:
                return Wording(template: app.t("notifications.followedYou"), parts: ["name": Part(text: actorName, emphasis: .strong)])
            case .comment, .mention, .like:
                // A comment on the viewer's poll or reply, a mention of them, or a like of their comment, read alike but for the verb
                let key = switch item.kind {
                case .mention: "notifications.mentioned"
                case .like: "ios.notifLiked"
                default: "notifications.commented"
                }
                return Wording(template: app.t(key), parts: ["name": Part(text: actorName, emphasis: .strong), "title": Part(text: title, emphasis: .titled)])
            case .closingSoon:
                guard let end = item.poll?.endTime, end > .now else {
                    return Wording(template: "{title}", parts: ["title": Part(text: title, emphasis: .titled)])
                }
                return Wording(template: app.t("notifications.endsIn"), parts: [
                    "title": Part(text: title, emphasis: .titled),
                    "duration": Part(text: app.dates.duration(end.timeIntervalSinceNow)),
                ])
            }
        }
    }

    private func styled(_ part: Part) -> Text {
        switch part.emphasis {
        case .plain: Text(part.text)
        case .strong: Text(part.text).fontWeight(.semibold)
        case .titled: Text(part.text).fontWeight(.medium).foregroundStyle(Tokens.foreground)
        }
    }

    private var line: Text {
        let wording = wording
        let text = Text.rich(wording.template, wording.parts.mapValues(styled))
        return wording.tail.map { text + Text(" · ") + styled($0) } ?? text
    }

    /// The same line as plain words, for VoiceOver. One pass, so a title that reads "{name}" stays as written.
    private var lineAccessibility: String {
        let wording = wording
        let text = Localizer.interpolate(wording.template, wording.parts.mapValues(\.text))
        return wording.tail.map { "\(text) · \($0.text)" } ?? text
    }

    // MARK: Meta

    /// Never a live count while a Poll is open: turnout only, and the outcome once it Ended.
    private var meta: [String] {
        let age = app.dates.age(item.createdAt)
        guard case .single = entry else { return [age] }
        switch item.kind {
        case .result:
            guard let poll = item.poll else { return [age] }
            return [winners(poll), app.t("poll.voted", ["count": app.t.number(poll.turnout)]), age].compactMap { $0 }
        case .cancelled:
            return [age]
        case .invitation:
            return [app.t("notifications.inviteOnly"), invitationWhen, age].compactMap { $0 }
        case .followed:
            return [age, item.actor?.displayName].compactMap { $0 }
        case .comment, .mention, .like:
            return [item.comment.map { app.t("notifications.excerpt", ["text": $0.excerpt]) }, age].compactMap { $0 }
        case .closingSoon:
            return [
                app.t("notifications.notVoted"),
                app.t("notifications.votedSoFar", ["count": app.t.number(item.poll?.turnout ?? 0)]),
                age,
            ]
        }
    }

    /// "Yes won" or "Tie between A and B"; nil when no Ballot named an option.
    private func winners(_ poll: FeedNotification.PollInfo) -> String? {
        guard let labels = poll.winningOptionLabels, let first = labels.first else { return nil }
        guard poll.tie == true else { return app.t("profile.wonBy", ["option": first]) }
        let list = app.t.list(labels)
        return app.t("profile.tieBetween", ["options": list])
    }

    /// The clock moves a Scheduled poll to Open and an Open one to closing; only Ended comes from the API.
    private var invitationStatus: PollStatus? {
        guard let poll = item.poll, let start = poll.startTime else { return nil }
        return Poll.status(active: !poll.isEnded, votingActive: true, startTime: start, endTime: poll.endTime)
    }

    private var invitationWhen: String? {
        guard let poll = item.poll, let start = poll.startTime, let status = invitationStatus else { return nil }
        return PollTiming(startTime: start, endTime: poll.endTime, status: status, t: app.t, dates: app.dates).when
    }

    // MARK: Action

    @ViewBuilder private var action: some View {
        switch entry {
        case .follows:
            Button(app.t("notifications.seeFollowers"), action: open).buttonStyle(.vm(.outline, size: .sm))
        case .single:
            switch item.kind {
            case .result:
                if let outcome = item.poll.flatMap(outcome) { OutcomeChip(outcome: outcome) }
            case .cancelled:
                EmptyView()
            case .invitation:
                let canVote = item.poll?.myOptionId == nil && (invitationStatus == .open || invitationStatus == .closing)
                Button(app.t(canVote ? "poll.vote" : "notifications.view"), action: open)
                    .buttonStyle(.vm(canVote ? .default : .outline, size: .sm))
            case .followed:
                if let actor = item.actor { FollowBackButton(user: actor, onFollow: read) }
            case .comment, .mention, .like:
                Button(app.t("comments.reply"), action: open).buttonStyle(.vm(.outline, size: .sm))
            case .closingSoon:
                if let end = item.poll?.endTime, end > .now {
                    Button(app.t("poll.vote"), action: open).buttonStyle(.vm(.outline, size: .sm))
                }
            }
        }
    }

    /// How the viewer's pick fared; nil without a Ballot to compare.
    private func outcome(_ poll: FeedNotification.PollInfo) -> BallotOutcome? {
        guard let won = poll.viewerWon else { return nil }
        if !won { return .lost }
        return poll.tie == true ? .tied : .won
    }
}

/// Follow back on a follower's row; once following, the button says so and unfollows.
private struct FollowBackButton: View {
    @Environment(AppModel.self) private var app
    let user: UserSummary
    let onFollow: () -> Void

    var body: some View {
        if app.isFollowing(user.id) {
            Button { app.unfollow(user.id) } label: {
                Label(app.t("follows.following"), systemImage: "checkmark").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.vm(.outline, size: .sm))
            .accessibilityHint(app.t("ios.unfollow", ["name": "@\(user.username)"]))
        } else {
            Button(app.t("follows.followBack")) {
                app.follow(user)
                onFollow()
            }
            .buttonStyle(.vm(.default, size: .sm))
        }
    }
}

/// What a signed-in-only tab shows to guests.
struct SignedOutPlaceholder: View {
    @Environment(AppModel.self) private var app
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).displayHeading(32)
                LoginPromptCard()
            }
            .pageColumn()
            .padding(.vertical, 24)
        }
    }
}

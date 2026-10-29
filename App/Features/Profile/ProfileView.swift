import SwiftUI
import VomattCore

/// The account tab: the signed-in user's own profile, or a sign-in prompt.
struct AccountTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if let me = app.me {
            AccountView(profile: me)
        } else if app.isSignedIn {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).canvas()
                .task { await app.refreshAccount() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(app.t("navigation.profile")).displayHeading(32)
                    LoginPromptCard()
                    AppSettingsSection()
                }
                .pageColumn()
                .padding(.vertical, 24)
            }
            .canvas()
        }
    }
}

/// `/<username>`: the viewer's own account page, or someone else's public profile (the web's `VisitorProfileView`):
/// who they are, their public record and the polls they asked. Follow sits where Edit profile sits on your own page.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    let username: String

    enum Phase { case loading, ready(UserProfile), notFound, failed }
    enum AskedFilter: Hashable { case all, open, ended }
    @State private var phase = Phase.loading
    @State private var polls: CursorList<Poll>?
    @State private var filter = AskedFilter.all

    var body: some View {
        Group {
            if let me = app.me, Username.isOwn(username, me: me.username) {
                AccountView(profile: me)
            } else {
                publicProfile
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var publicProfile: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch phase {
                case .loading:
                    ProfileSkeleton()
                case .notFound:
                    VStack(alignment: .leading, spacing: 12) {
                        Text(app.t("profile.notFoundTitle")).displayHeading(28)
                        Text(app.t("profile.notFoundBody")).font(.vmBody).foregroundStyle(Tokens.mutedForeground)
                    }
                case .failed:
                    LoadFailed(message: app.t("profile.cardFailed")) { await load() }
                case let .ready(profile):
                    content(profile)
                }
            }
            .pageColumn(768)
            .padding(.vertical, 24)
        }
        .refreshable { await load() }
        .canvas()
        .toolbar {
            if let readyProfile {
                ToolbarItem(placement: .topBarTrailing) { moreMenu(readyProfile) }
            }
        }
        // Signing in or out changes what the profile says about the viewer (follows, blocks)
        .task(id: "\(username) \(app.sessionGeneration)") { await load() }
    }

    private var readyProfile: UserProfile? {
        if case let .ready(profile) = phase { profile } else { nil }
    }

    @ViewBuilder private func content(_ profile: UserProfile) -> some View {
        let visible = profile.mutualFollowersPreview.filter { !app.isBlocked($0.username) }
        let hidden = profile.mutualFollowersPreview.count - visible.count
        ProfileHeader(profile: profile)
        VStack(alignment: .leading, spacing: 12) {
            FollowCounts(username: profile.username, followers: followersCount(profile), following: profile.followingCount)
            if app.isSignedIn, let line = MutualFollowersLine(count: profile.mutualFollowersCount.map { $0 - hidden }, preview: visible, t: app.t) {
                MutualFollowersView(line: line) { app.push(.people(username: profile.username, kind: .mutual)) }
            }
        }
        ProfileFollowButton(profile: profile)
        StatsGrid(stats: [
            .init(label: app.t("profile.recordAsked"), value: app.t.number(profile.totalPolls)),
            .init(label: app.t("profile.recordVoted"), value: app.t.number(profile.totalVotes)),
        ])
        if let polls { askedList(polls, total: profile.totalPolls) }
    }

    /// The follower count with the viewer's own follow or unfollow since the profile loaded.
    private func followersCount(_ profile: UserProfile) -> Int {
        let delta = (app.isFollowing(profile.id) ? 1 : 0) - (profile.isFollowing == true ? 1 : 0)
        return profile.followersCount + delta
    }

    /// Share profile and Copy link for anyone; Block… or Unblock signed in, as the web's ••• menu.
    private func moreMenu(_ profile: UserProfile) -> some View {
        let url = app.config.profileURL(profile.username)
        return Menu {
            ShareLink(item: url) { Label(app.t("ios.shareProfile"), systemImage: "square.and.arrow.up") }
            Button {
                UIPasteboard.general.url = url
                app.showToast(app.t("comments.linkCopied"))
            } label: { Label(app.t("comments.copyLink"), systemImage: "link") }
            if app.isSignedIn, profile.id != nil {
                Divider()
                if app.isBlocked(profile.username) {
                    Button(role: .destructive) {
                        app.unblock(profile.username)
                        app.showToast(app.t("blocks.unblocked", ["username": profile.username]))
                    } label: { Label(app.t("blocks.unblock"), systemImage: "nosign") }
                } else {
                    Button(role: .destructive) { app.blockRequest = .init(username: profile.username, userId: profile.id) } label: {
                        Label(app.t("blocks.blockEllipsis"), systemImage: "nosign")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel(app.t("profile.moreFor", ["username": profile.username]))
    }

    /// Their polls, Open (and opening soon) first, then Ended; filtered over the pages loaded so far.
    @ViewBuilder private func askedList(_ polls: CursorList<Poll>, total: Int) -> some View {
        // A profile still lists the polls of someone you blocked, as the API does; only deletions drop out
        let split = ProfileLists.splitAsked(polls.items.filter { !app.deletedPollIds.contains($0.id) }.map(app.latest))
        let open = filter == .ended ? [] : split.open
        let ended = filter == .open ? [] : split.ended
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                SectionTitle(text: app.t("profile.tabAsked"))
                TabCount(count: total)
            }
            FilterPills(label: app.t("profile.filterLabel"), selection: $filter, options: [
                (AskedFilter.all, app.t("profile.filterAll"), nil),
                (AskedFilter.open, app.t("profile.filterOpen"), nil),
                (AskedFilter.ended, app.t("myPolls.tabEnded"), nil),
            ])
            switch polls.phase {
            case .idle, .loading:
                VStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in PollRowSkeleton() } }
            case .failed:
                LoadFailed(message: app.t("profile.pollsLoadFailed")) { await polls.reload() }
            case .loaded:
                if split.open.isEmpty, split.ended.isEmpty {
                    EmptyState { Text(app.t("profile.noPollsYet")) }
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        // Counts are exact only once every page is in
                        if !open.isEmpty {
                            ProfileSection(label: app.t("profile.sectionOpen"), count: polls.hasMore ? nil : open.count)
                            ForEach(open) { AskedRow(poll: $0) }
                        }
                        if !ended.isEmpty {
                            ProfileSection(label: app.t("myPolls.tabEnded"), count: polls.hasMore ? nil : ended.count)
                            ForEach(ended) { AskedRow(poll: $0) }
                        }
                        if open.isEmpty, ended.isEmpty, !polls.hasMore {
                            EmptyState { Text(app.t("myPolls.empty")) }
                        }
                    }
                    LoadMoreFooter(list: polls)
                }
            }
        }
    }

    private func load() async {
        let service = app.service
        let name = username
        let list = polls ?? CursorList { try await service.userPolls(username: name, cursor: $0) }
        polls = list
        do {
            guard let profile = try await service.userProfile(username: username) else {
                phase = .notFound
                return
            }
            phase = .ready(profile)
            await list.reload()
        } catch {
            if case .ready = phase { return }
            phase = .failed
        }
    }
}

/// "12 followers" and "3 following", each a button to its list. The lists need an account, so guests get plain counts.
struct FollowCounts: View {
    @Environment(AppModel.self) private var app
    let username: String
    let followers: Int
    let following: Int

    var body: some View {
        HStack(spacing: 8) {
            count(app.t.count("profile.followersCount", followers), .followers)
            count(app.t.count("profile.followingCount", following), .following)
        }
    }

    @ViewBuilder private func count(_ label: String, _ kind: FollowListKind) -> some View {
        if app.isSignedIn {
            Button(label) { app.push(.people(username: username, kind: kind)) }.buttonStyle(.vm(.outline, size: .sm))
        } else {
            Text(label).font(.vm(14)).foregroundStyle(Tokens.mutedForeground).padding(.trailing, 8)
        }
    }
}

/// The mutual followers line: up to two small stacked avatars and who they are, a button to the whole list.
struct MutualFollowersView: View {
    @Environment(AppModel.self) private var app
    let line: MutualFollowersLine
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                HStack(spacing: -10) {
                    ForEach(line.shown) { AvatarView(username: $0.username, avatarUrl: $0.avatarUrl, size: 16) }
                }
                .accessibilityHidden(true)
                Text(line.text).multilineTextAlignment(.leading)
            }
            .font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
        }
        .buttonStyle(.plain)
        .accessibilityHint(app.t("profile.mutualFollowers"))
    }
}

/// Follow, Follow back or Following for someone else's profile, full width under the header (the web's
/// `FollowButton`). Following unfollows on the tap, no confirm: one tap undoes it. Blocked in its place once
/// the viewer blocked them, as unblocking lives in the ••• menu and Settings. Nothing signed out.
struct ProfileFollowButton: View {
    @Environment(AppModel.self) private var app
    let profile: UserProfile

    var body: some View {
        if app.isSignedIn, let id = profile.id, id != app.userId {
            if app.isBlocked(profile.username) {
                Text(app.t("blocks.blockedBadge"))
                    .font(.vm(14, .medium)).foregroundStyle(Tokens.mutedForeground)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minTarget)
                    .background(Tokens.secondary, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Tokens.border))
            } else if app.isFollowing(id) {
                Button { app.unfollow(id) } label: { Label(app.t("follows.following"), systemImage: "checkmark") }
                    .buttonStyle(.vm(.outline, size: .sm, fullWidth: true))
                    .accessibilityAddTraits(.isSelected)
                    .accessibilityHint(app.t("follows.unfollow"))
            } else {
                let followBack = profile.followsYou == true
                Button {
                    app.follow(UserSummary(id: id, username: profile.username, displayName: profile.displayName, avatarUrl: profile.avatarUrl))
                } label: {
                    if followBack {
                        Text(app.t("follows.followBack"))
                    } else {
                        Label(app.t("follows.follow"), systemImage: "plus")
                    }
                }
                .buttonStyle(.vm(.default, size: .sm, fullWidth: true))
            }
        }
    }
}

struct ProfileSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(spacing: 16) {
                Skeleton(height: 64, width: 64, radius: 32)
                VStack(alignment: .leading, spacing: 8) { Skeleton(height: 28, width: 180); Skeleton(height: 14, width: 100) }
            }
            Skeleton(height: 80, radius: Radius.xl)
            Skeleton(height: 88, radius: Radius.xl)
        }
    }
}

/// Avatar, name, @username, bio and the public details line (the web's `ProfileHeader`).
struct ProfileHeader<Action: View>: View {
    @Environment(AppModel.self) private var app
    let profile: UserProfile
    var onAvatarTap: (() -> Void)?
    @ViewBuilder var action: () -> Action

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Group {
                if let onAvatarTap {
                    Button(action: onAvatarTap) {
                        AvatarView(username: profile.username, avatarUrl: profile.avatarUrl, size: 64)
                            .overlay(alignment: .bottomTrailing) {
                                Image(systemName: "pencil").font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Tokens.primaryForeground)
                                    .frame(width: 22, height: 22).background(Tokens.primary, in: Circle())
                                    .overlay(Circle().strokeBorder(Tokens.background, lineWidth: 2))
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.t("avatar.change"))
                } else {
                    AvatarView(username: profile.username, avatarUrl: profile.avatarUrl, size: 64)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.displayName ?? profile.username).displayHeading(28).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if profile.displayName != nil {
                    Text("@\(profile.username)").font(.vmMono(14)).foregroundStyle(Tokens.mutedForeground)
                }
                if let bio = profile.bio, !bio.isEmpty {
                    Text(bio).font(.vm(14)).foregroundStyle(Tokens.foreground)
                }
                Text(details.joined(separator: " · ")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action()
        }
    }

    /// "location · points · membership · joined"; fields the owner hid come back nil and drop out.
    private var details: [String] {
        [
            profile.location,
            profile.points.map { app.t("profile.points", ["count": app.t.number($0)]) },
            profile.membershipLevel.map { app.t("profile.membership", ["level": $0]) },
            profile.joinedAt.map { app.t("profile.joined", ["date": app.dates.monthYear($0)]) },
        ].compactMap { $0 }
    }
}

extension ProfileHeader where Action == EmptyView {
    init(profile: UserProfile) {
        self.init(profile: profile, onAvatarTap: nil, action: { EmptyView() })
    }
}

/// The numbers grid: hairline-separated cells on the card color (the web's `ProfileRecord`).
struct StatsGrid: View {
    struct Stat {
        let label: String
        let value: String
        /// Only the owner sees it: marked with the lock.
        var onlyYou = false
    }

    let stats: [Stat]
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stat.value).font(.vmMono(28)).tracking(-0.5).foregroundStyle(Tokens.foreground)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    HStack(spacing: 4) {
                        Text(stat.label)
                        if stat.onlyYou { OnlyYouMarker() }
                    }
                    .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Tokens.card)
                .accessibilityElement(children: .combine)
            }
        }
        .background(Tokens.border)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
    }
}

/// Marks what only the owner can see: a lock, named for VoiceOver.
struct OnlyYouMarker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10))
            .foregroundStyle(Tokens.mutedForeground)
            .accessibilityLabel(app.t("profile.onlyYou"))
    }
}

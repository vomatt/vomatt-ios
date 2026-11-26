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
                .navigationTitle(app.t("navigation.profile"))
                .navigationBarTitleDisplayMode(.inline)
                .task { await app.refreshAccount() }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LoginPromptCard()
                    LegalLinks()
                }
                .pageColumn()
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .canvas()
            .navigationTitle(app.t("navigation.profile"))
            .navigationBarTitleDisplayMode(.large)
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
        .navigationTitle("@\(username)")
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
            // A community account can't follow anyone
            FollowCounts(username: profile.username, followers: followersCount(profile), following: profile.isCommunity ? nil : profile.followingCount)
            if app.isSignedIn, let line = MutualFollowersLine(count: profile.mutualFollowersCount.map { $0 - hidden }, preview: visible, t: app.t) {
                MutualFollowersView(line: line) { app.push(.people(username: profile.username, kind: .mutual)) }
            }
        }
        ProfileFollowButton(profile: profile)
        // Nor does it vote
        StatsGrid(stats: [
            .init(label: app.t("profile.recordAsked"), value: app.t.number(profile.totalPolls)),
        ] + (profile.isCommunity ? [] : [
            .init(label: app.t("profile.recordVoted"), value: app.t.number(profile.totalVotes)),
        ]), columns: profile.isCommunity ? 1 : 2)
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
            if app.isSignedIn, profile.id != nil, profile.id != app.userId {
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
    /// nil leaves the count out.
    let following: Int?

    var body: some View {
        HStack(spacing: 8) {
            count(app.t.count("profile.followersCount", followers), .followers)
            if let following { count(app.t.count("profile.followingCount", following), .following) }
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
                FollowingButton(userId: id, username: profile.username, fullWidth: true)
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

/// Avatar, name, @username, bio and when they joined (the web's `ProfileHeader`). The name leads with the
/// real name, then the display name (`ProfileName`). A community account is a group: it has no real name.
struct ProfileHeader<Action: View>: View {
    @Environment(AppModel.self) private var app
    let profile: UserProfile
    var onAvatarTap: (() -> Void)?
    /// Fields visitors don't see; only the owner's header passes them, and each gets a lock.
    var hiddenFields: Set<String> = []
    @ViewBuilder var action: () -> Action

    /// As on the web's phone layout, the name gets a row of its own under the avatar and actions, so it wraps instead of truncating.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                avatar
                Spacer(minLength: 0)
                action()
            }
            details
        }
    }

    @ViewBuilder private var avatar: some View {
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

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameLine.displayHeading(19).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(nameSpoken)
                .accessibilityAddTraits(.isHeader)
            Text("@\(profile.username)").font(.vmMono(14)).foregroundStyle(Tokens.mutedForeground)
            if let bio = profile.bio, !bio.isEmpty {
                marked(bio, "bio", lockSize: 11).font(.vm(14)).foregroundStyle(Tokens.foreground)
                    .accessibilityLabel(spoken(bio, "bio"))
            }
            if let meta {
                meta.font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                    .accessibilityLabel([genderMeta.map { spoken($0, "gender") }, joinedText].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A community account is a group: it has no gender either.
    private var genderMeta: String? {
        guard !profile.isCommunity, let gender = profile.gender else { return nil }
        return app.t("profile.genderMeta", ["gender": app.t(gender.translationKey)])
    }

    private var joinedText: String? {
        profile.joinedAt.map { app.t("profile.joined", ["date": app.dates.monthYear($0)]) }
    }

    /// "Gender: Female · Joined Aug 2026", the gender only where the API gave one.
    private var meta: Text? {
        let parts = [genderMeta.map { marked($0, "gender", lockSize: 10) }, joinedText.map { Text($0) }].compactMap { $0 }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { $0 + Text(verbatim: metaGap) + $1 }
    }

    private var firstName: String? { profile.isCommunity ? nil : profile.firstName }
    private var lastName: String? { profile.isCommunity ? nil : profile.lastName }

    private var name: ProfileName {
        ProfileName(username: profile.username, displayName: profile.displayName, firstName: firstName, lastName: lastName)
    }

    /// The field whose lock the leading name carries: the real name's halves, or the display name.
    private var primaryField: String {
        guard ProfileName.realName(firstName: firstName, lastName: lastName) != nil else { return "displayName" }
        return hiddenFields.contains("firstName") ? "firstName" : "lastName"
    }

    private var nameLine: Text {
        let primary = marked(name.primary, primaryField, lockSize: 14)
        guard let secondary = name.secondary else { return primary }
        return primary + Text(verbatim: " ") + marked(secondary, "displayName", lockSize: 14).foregroundStyle(Tokens.mutedForeground)
    }

    private var nameSpoken: String {
        [spoken(name.primary, primaryField), name.secondary.map { spoken($0, "displayName") }].compactMap { $0 }.joined(separator: ", ")
    }

    /// `text`, then a lock when only the owner sees `field`.
    private func marked(_ text: String, _ field: String, lockSize: CGFloat) -> Text {
        guard hiddenFields.contains(field) else { return Text(text) }
        return Text(text) + Text(verbatim: " ") + Text(Image(systemName: "lock.fill")).font(.system(size: lockSize)).foregroundStyle(Tokens.mutedForeground)
    }

    private func spoken(_ text: String, _ field: String) -> String {
        hiddenFields.contains(field) ? "\(text) (\(app.t("profile.onlyYou")))" : text
    }
}

/// "Following", which asks before it unfollows (the web's `FollowButton` and `UnfollowDialog`).
struct FollowingButton: View {
    @Environment(AppModel.self) private var app
    let userId: String
    let username: String
    var fullWidth = false

    var body: some View {
        Button { app.unfollowRequest = .init(userId: userId, username: username) } label: {
            Label(app.t("follows.following"), systemImage: "checkmark").labelStyle(.titleAndIcon)
        }
        .buttonStyle(.vm(.outline, size: .sm, fullWidth: fullWidth))
        .accessibilityAddTraits(.isSelected)
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
        /// Opens the list this count counts; the whole cell is the target.
        var onSelect: (() -> Void)?
    }

    let stats: [Stat]
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                if let onSelect = stat.onSelect {
                    Button(action: onSelect) { cell(stat) }.buttonStyle(.plain)
                } else {
                    cell(stat)
                }
            }
        }
        .background(Tokens.border)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
    }

    private func cell(_ stat: Stat) -> some View {
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
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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

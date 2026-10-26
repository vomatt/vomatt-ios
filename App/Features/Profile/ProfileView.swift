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

/// `/<username>`: the viewer's own account page, or someone else's public profile.
struct ProfileView: View {
    @Environment(AppModel.self) private var app
    let username: String

    enum Phase { case loading, ready(UserProfile), notFound, failed }
    @State private var phase = Phase.loading
    @State private var polls: CursorList<Poll>?

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
            VStack(alignment: .leading, spacing: 32) {
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
                    ProfileHeader(profile: profile, onAvatarTap: nil) { ProfileRelationButton(profile: profile) }
                    VStack(alignment: .leading, spacing: 12) {
                        FollowCounts(username: profile.username, followers: profile.followersCount, following: profile.followingCount)
                        if profile.followsYou == true { Chip(text: app.t("ios.followsYou")) }
                        MutualFollowers(profile: profile)
                    }
                    StatsGrid(stats: [
                        (app.t("account.votesCast"), app.t.number(profile.totalVotes)),
                        (app.t("account.pollsCreated"), app.t.number(profile.totalPolls)),
                    ])
                    .accessibilityLabel(app.t("profile.stats"))
                    VStack(alignment: .leading, spacing: 16) {
                        SectionTitle(text: app.t("profile.polls"))
                        if let polls {
                            let items = app.visible(polls.items)
                            if polls.phase == .loaded, items.isEmpty {
                                EmptyState { Text(app.t("profile.noPollsYet")) }
                            }
                            LazyVStack(spacing: 8) {
                                ForEach(items) { poll in
                                    PollRow(poll: poll) {
                                        Text(app.t("poll.voted", ["count": app.t.number(poll.turnout ?? 0)]))
                                    } aside: {
                                        StatusChip(poll: poll)
                                    }
                                }
                            }
                            LoadMoreFooter(list: polls)
                        }
                    }
                }
            }
            .pageColumn(768)
            .padding(.vertical, 24)
        }
        .refreshable { await load() }
        .canvas()
        .task(id: username) { await load() }
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
            count(app.t("ios.followersCount", ["count": app.t.number(followers)]), .followers)
            count(app.t("ios.followingCount", ["count": app.t.number(following)]), .following)
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

/// "Followed by @jtan and 2 more you follow": the followers of this user whom the viewer follows.
/// Hidden for guests, on your own profile and when there are none.
struct MutualFollowers: View {
    @Environment(AppModel.self) private var app
    let profile: UserProfile

    var body: some View {
        let visible = profile.mutualFollowersPreview.filter { !app.isBlocked($0.username) }
        let names = visible.map(\.username)
        let hidden = profile.mutualFollowersPreview.count - visible.count
        if app.isSignedIn, let count = profile.mutualFollowersCount, case let total = count - hidden, total > 0, let first = names.first {
            Button { app.push(.people(username: profile.username, kind: .mutual)) } label: {
                Text(summary(first: first, second: names.count > 1 ? names[1] : nil, total: total))
                    .font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityHint(app.t("ios.mutualTitle"))
        }
    }

    private func summary(first: String, second: String?, total: Int) -> String {
        guard let second, total > 1 else { return app.t("ios.mutualOne", ["a": first]) }
        if total == 2 { return app.t("ios.mutualTwo", ["a": first, "b": second]) }
        return app.t("ios.mutualMore", ["a": first, "b": second, "count": total - 2])
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

/// The numbers grid: hairline-separated cells on the card color.
struct StatsGrid: View {
    let stats: [(label: String, value: String)]
    var columns = 2

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: columns), spacing: 1) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                VStack(alignment: .leading, spacing: 8) {
                    Text(stat.value).font(.vmMono(28)).tracking(-0.5).foregroundStyle(Tokens.foreground)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(stat.label).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
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

import SwiftUI
import VomattCore

/// Who follows a user, whom they follow, or which of their followers the viewer follows too
/// (signed in only), newest first.
struct FollowListView: View {
    @Environment(AppModel.self) private var app
    let username: String
    let kind: FollowListKind
    @State private var list: CursorList<UserSummary>?

    private var title: String {
        switch kind {
        case .followers: app.t("profile.followers")
        case .following: app.t("profile.following")
        case .mutual: app.t("ios.mutualTitle")
        }
    }

    private var emptyText: String {
        switch kind {
        case .followers: app.t("ios.followersEmpty")
        case .following: app.t("ios.followingListEmpty")
        case .mutual: app.t("ios.mutualEmpty")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: title)
                if let list {
                    switch list.phase {
                    case .idle, .loading:
                        VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 56, radius: Radius.xl) } }
                    case .failed:
                        LoadFailed(message: app.t("profile.cardFailed")) { await list.reload() }
                    case .loaded:
                        let items = list.items.filter { !app.isBlocked($0.username) }
                        if items.isEmpty {
                            EmptyState { Text(emptyText) }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(items) { user in
                                    HStack(spacing: 8) {
                                        UserChip(username: user.username, avatarUrl: user.avatarUrl, avatarSize: 28).font(.vm(15))
                                        if user.followsYou == true { Chip(text: app.t("ios.followsYou")) }
                                        Spacer()
                                        PersonFollowButton(user: user)
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 56)
                                    .overlay(alignment: .bottom) {
                                        if user.id != items.last?.id { Hairline() }
                                    }
                                }
                            }
                            .card(padding: nil)
                            LoadMoreFooter(list: list)
                        }
                    }
                }
            }
            .pageColumn(768)
            .padding(.vertical, 24)
        }
        .refreshable { await list?.reload() }
        .canvas()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: username) {
            let service = app.service
            let name = username
            let kind = kind
            let list = CursorList<UserSummary> {
                switch kind {
                case .followers: try await service.followers(username: name, cursor: $0)
                case .following: try await service.following(username: name, cursor: $0)
                case .mutual: try await service.mutualFollowers(username: name, cursor: $0)
                }
            }
            self.list = list
            await list.reload()
        }
    }
}

/// Follow, Follow back or Following (which asks before it unfollows) for a person in a list; nothing for yourself.
struct PersonFollowButton: View {
    @Environment(AppModel.self) private var app
    let user: UserSummary

    var body: some View {
        if app.isSignedIn, user.id != app.userId {
            if app.isFollowing(user.id) {
                FollowingButton(userId: user.id, username: user.username)
            } else {
                Button(app.t(user.followsYou == true ? "ios.followBack" : "ios.followShort")) { app.follow(user) }
                    .buttonStyle(.vm(.default, size: .sm))
            }
        }
    }
}

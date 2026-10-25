import SwiftUI
import VomattCore

/// Who follows a user, or whom they follow (signed in only), newest first.
struct FollowListView: View {
    @Environment(AppModel.self) private var app
    let username: String
    let followers: Bool
    @State private var list: CursorList<UserSummary>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(text: app.t(followers ? "profile.followers" : "profile.following"))
                if let list {
                    switch list.phase {
                    case .idle, .loading:
                        VStack(spacing: 8) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 56, radius: Radius.xl) } }
                    case .failed:
                        LoadFailed(message: app.t("profile.cardFailed")) { await list.reload() }
                    case .loaded:
                        if list.items.isEmpty {
                            EmptyState { Text(app.t(followers ? "ios.followersEmpty" : "ios.followingListEmpty")) }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(list.items) { user in
                                    HStack {
                                        UserChip(username: user.username, avatarUrl: user.avatarUrl, avatarSize: 28).font(.vm(15))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 56)
                                    .overlay(alignment: .bottom) {
                                        if user.id != list.items.last?.id { Rectangle().fill(Tokens.border).frame(height: 1) }
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
            let isFollowers = followers
            let list = CursorList<UserSummary> {
                isFollowers ? try await service.followers(username: name, cursor: $0) : try await service.following(username: name, cursor: $0)
            }
            self.list = list
            await list.reload()
        }
    }
}

/// Follow / unfollow, or unblock, for someone else's profile (signed in only).
struct ProfileRelationButton: View {
    @Environment(AppModel.self) private var app
    let profile: UserProfile

    var body: some View {
        if app.isSignedIn, let id = profile.id, id != app.userId {
            if app.isBlocked(profile.username) {
                Button(app.t("ios.unblock")) { app.unblock(profile.username) }.buttonStyle(.vm(.outline, size: .sm))
            } else if app.isFollowing(id) {
                Button(app.t("ios.unfollowShort")) { app.unfollow(id) }.buttonStyle(.vm(.outline, size: .sm))
            } else {
                Button(app.t("ios.followShort")) {
                    app.follow(UserSummary(id: id, username: profile.username, displayName: profile.displayName, avatarUrl: profile.avatarUrl))
                }
                .buttonStyle(.vm(.default, size: .sm))
            }
        }
    }
}

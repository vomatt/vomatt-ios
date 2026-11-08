import SwiftUI
import VomattCore

/// The home tab: feed and topic pills over the feed (the web's home page).
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var tags: [Tag] = []
    @State private var activeTag: Tag?
    @State private var picked = HomeFeed.forYou
    @State private var resultsUnread = false

    /// Signing out leaves the feeds that are only offered while signed in.
    private var feed: HomeFeed { app.isSignedIn ? picked : .forYou }

    var body: some View {
        FeedView(tag: feed == .forYou ? activeTag : nil, feed: feed, header: AnyView(topicPills))
            .id(feed == .forYou ? activeTag?.id : feed.rawValue)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("brand-logo").renderingMode(.template).resizable().scaledToFit()
                        .frame(height: 18).foregroundStyle(Tokens.foreground)
                        .accessibilityLabel("vomatt")
                }
            }
            .task { if tags.isEmpty { tags = await app.service.popularTags() } }
            .task(id: "\(app.sessionGeneration) \(feed)") { await loadResultsUnread() }
    }

    /// The web's `HomepageHeader`: For you, then Following, Results are in and Closing soon when
    /// signed in, then the popular topics.
    private var topicPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HomeFeed.allCases.filter { app.isSignedIn || $0 == .forYou }, id: \.self) { kind in
                    PillButton(
                        title: app.t(Self.label(kind)),
                        isOn: feed == kind && activeTag == nil,
                        unread: kind == .resultsIn && resultsUnread ? app.t("notifications.unread") : nil
                    ) {
                        picked = kind
                        activeTag = nil
                    }
                }
                ForEach(tags) { tag in
                    PillButton(title: tag.name, isOn: feed == .forYou && tag.id == activeTag?.id) {
                        picked = .forYou
                        activeTag = tag
                    }
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.t("homePage.topics"))
    }

    private static func label(_ feed: HomeFeed) -> String {
        switch feed {
        case .forYou: "homePage.allTopics"
        case .following: "homePage.following"
        case .resultsIn: "homePage.resultsIn"
        case .closingSoon: "homePage.closingSoon"
        }
    }

    /// The Results are in pill's dot: whether a result on that feed's first page is unread.
    private func loadResultsUnread() async {
        guard app.isSignedIn else {
            resultsUnread = false
            return
        }
        guard let page = try? await app.service.resultsInFeed() else { return }
        resultsUnread = app.visible(page.items).contains { $0.unread == true }
    }
}

/// One of the home feeds; For you optionally under one topic.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    let tag: Tag?
    var feed = HomeFeed.forYou
    var header: AnyView?
    @State private var list: CursorList<Poll>?

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Guests get the login prompt above the topics
                if !app.isSignedIn {
                    LoginPromptCard().pageColumn(560).padding(.top, 8)
                    LegalLinks(pagesOnly: true).padding(.horizontal, 4).pageColumn(560).padding(.bottom, 8)
                }
                LazyVStack(alignment: .leading, spacing: 16, pinnedViews: [.sectionHeaders]) {
                    Section {
                        content.pageColumn(560)
                    } header: {
                        if let header { header.background(Tokens.background.opacity(0.97)) }
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .refreshable { await list?.reload() }
        .canvas()
        .navigationTitle(tag.map { "#\($0.name)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.sessionGeneration) {
            let list = list ?? makeList()
            self.list = list
            await list.reload()
        }
    }

    @ViewBuilder private var content: some View {
        if let list {
            switch list.phase {
            case .idle, .loading:
                ForEach(0..<3, id: \.self) { index in PollCardSkeleton(options: 3 + index % 2) }.padding(.top, 4)
            case .failed:
                LoadFailed(message: app.t("homePage.feedFailed")) { await list.reload() }
            case .loaded:
                let polls = app.visible(list.items)
                if let tag, app.isSignedIn { TopicFollowButton(tag: tag).padding(.top, 4) }
                // Not while pages remain: a feed that filters a list can come back empty before its end
                if polls.isEmpty && !list.hasMore {
                    empty
                } else {
                    ForEach(polls) { poll in
                        PollCardView(poll: poll) {
                            list.update { $0.removeAll { $0.id == poll.id } }
                        }
                    }
                    LoadMoreFooter(list: list)
                }
            }
        }
    }

    @ViewBuilder private var empty: some View {
        switch feed {
        case .forYou:
            EmptyCard(title: app.t(tag == nil ? "homePage.feedListNoData" : "homePage.topicEmpty")) {
                Button(app.t(app.isSignedIn ? "homePage.createFirst" : "homePage.joinToCreate")) { app.openCreator() }
                    .buttonStyle(.vm)
            }
        case .following:
            EmptyCard(title: app.t("homePage.followingEmpty"), body: app.t("homePage.followingEmptyHint")) {
                Button(app.t("homePage.followingEmptyCta")) { app.select(.explore) }
                    .buttonStyle(.vm(.outline))
            }
        case .resultsIn:
            EmptyCard(title: app.t("homePage.resultsInEmpty"), body: app.t("homePage.resultsInEmptyHint"))
        case .closingSoon:
            EmptyCard(title: app.t("homePage.closingSoonEmpty"), body: app.t("homePage.closingSoonEmptyHint"))
        }
    }

    private func makeList() -> CursorList<Poll> {
        let service = app.service
        let (feed, slug) = (feed, tag?.slug)
        return CursorList { cursor in try await service.feed(feed, cursor: cursor, tag: slug) }
    }
}

/// On a topic's feed: following the topic adds its Open Public Polls to the Following feed; one tap undoes it
/// (the web's `TopicFollowButton`). Shown once the followed topics are known.
private struct TopicFollowButton: View {
    @Environment(AppModel.self) private var app
    let tag: Tag
    @State private var following: Bool?
    @State private var isSaving = false

    var body: some View {
        Group {
            if let following {
                Button { Task { await toggle(to: !following) } } label: {
                    Label(app.t(following ? "homePage.followingTopic" : "homePage.followTopic"), systemImage: following ? "checkmark" : "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.vm(following ? .outline : .default, size: .sm))
                .disabled(isSaving)
                .accessibilityAddTraits(following ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: tag.id) {
            if let followed = try? await app.service.followedTags() { following = followed.contains { $0.id == tag.id } }
        }
    }

    private func toggle(to next: Bool) async {
        following = next
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.service.setTagFollow(tagId: tag.id, following: next)
        } catch {
            following = !next
            app.showToast(app.t.message(for: error, fallback: next ? "homePage.followTopicFailed" : "homePage.unfollowTopicFailed"), isError: true)
        }
    }
}

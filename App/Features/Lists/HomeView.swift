import SwiftUI
import VomattCore

/// The home tab: topic tabs over the feed.
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var tags: [Tag] = []
    @State private var activeTag: Tag?
    @State private var showFollowing = false

    /// Signing out leaves the Following tab, which is only offered while signed in.
    private var followingActive: Bool { showFollowing && app.isSignedIn }

    var body: some View {
        FeedView(tag: followingActive ? nil : activeTag, following: followingActive, header: AnyView(topicTabs))
            .id(followingActive ? "following" : activeTag?.id)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Image("brand-logo").renderingMode(.template).resizable().scaledToFit()
                        .frame(height: 18).foregroundStyle(Tokens.foreground)
                        .accessibilityLabel("vomatt")
                }
            }
            .task { if tags.isEmpty { tags = await app.service.popularTags() } }
    }

    /// The web's `HomepageHeader`: "For you" plus the popular topics.
    private var topicTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                topicTab(nil, label: app.t("homePage.allTopics"))
                if app.isSignedIn { followingTab }
                ForEach(tags) { tag in topicTab(tag, label: "#\(tag.name)") }
            }
            .padding(.horizontal, Metrics.gutter - 4)
        }
        // Behind the tabs, so the active underline covers it (as in `LineTabs`)
        .background(alignment: .bottom) { Rectangle().fill(Tokens.border).frame(height: 1) }
        .accessibilityLabel(app.t("homePage.topics"))
    }

    private var followingTab: some View {
        tabButton(app.t("profile.following"), isActive: followingActive) { showFollowing = true; activeTag = nil }
    }

    private func topicTab(_ tag: Tag?, label: String) -> some View {
        tabButton(label, isActive: !followingActive && tag?.id == activeTag?.id) { showFollowing = false; activeTag = tag }
    }

    private func tabButton(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.vm(14, .medium))
                .foregroundStyle(isActive ? Tokens.foreground : Tokens.mutedForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .fixedSize()
                .overlay(alignment: .bottom) {
                    if isActive { Rectangle().fill(Tokens.foreground).frame(height: 2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

/// Open Public Polls, most recently opened first, optionally under one topic.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    let tag: Tag?
    /// Open Public Polls by followed people instead of the whole feed.
    var following = false
    var header: AnyView?
    @State private var list: CursorList<Poll>?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                Section {
                    content.pageColumn(560)
                } header: {
                    if let header { header.background(Tokens.background.opacity(0.97)) }
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
                ForEach(0..<3, id: \.self) { _ in PollCardSkeleton() }.padding(.top, 4)
            case .failed:
                LoadFailed(message: app.t("homePage.feedFailed")) { await list.reload() }
            case .loaded:
                let polls = app.visible(list.items)
                if polls.isEmpty {
                    if following { followingEmpty } else { empty }
                } else {
                    if !app.isSignedIn { LoginPromptCard().padding(.top, 4) }
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

    private var empty: some View {
        VStack(spacing: 24) {
            Text(app.t(tag == nil ? "homePage.feedListNoData" : "homePage.topicEmpty"))
                .displayHeading(30).multilineTextAlignment(.center)
            Button(app.t(app.isSignedIn ? "homePage.createFirst" : "homePage.joinToCreate")) { app.openCreator() }
                .buttonStyle(.vm)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }

    private var followingEmpty: some View {
        EmptyState { Text(app.t("ios.followingEmpty")) }.padding(.top, 4)
    }

    private func makeList() -> CursorList<Poll> {
        let service = app.service
        if following { return CursorList { cursor in try await service.followingPolls(cursor: cursor, limit: 10) } }
        let slug = tag?.slug
        return CursorList { cursor in try await service.polls(tag: slug, cursor: cursor, limit: 10) }
    }
}

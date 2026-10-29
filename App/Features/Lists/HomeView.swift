import SwiftUI
import VomattCore

/// The home tab: topic pills over the feed (the web's home page).
struct HomeView: View {
    @Environment(AppModel.self) private var app
    @State private var tags: [Tag] = []
    @State private var activeTag: Tag?
    @State private var showFollowing = false

    /// Signing out leaves the Following tab, which is only offered while signed in.
    private var followingActive: Bool { showFollowing && app.isSignedIn }

    var body: some View {
        FeedView(tag: followingActive ? nil : activeTag, following: followingActive, header: AnyView(topicPills))
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

    /// The web's `HomepageHeader`: For you, Following when signed in, then the popular topics.
    private var topicPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PillButton(title: app.t("homePage.allTopics"), isOn: !followingActive && activeTag == nil) {
                    showFollowing = false
                    activeTag = nil
                }
                if app.isSignedIn {
                    PillButton(title: app.t("homePage.following"), isOn: followingActive) {
                        showFollowing = true
                        activeTag = nil
                    }
                }
                ForEach(tags) { tag in
                    PillButton(title: tag.name, isOn: !followingActive && tag.id == activeTag?.id) {
                        showFollowing = false
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
}

/// Open Public Polls, most recently opened first, optionally under one topic.
struct FeedView: View {
    @Environment(AppModel.self) private var app
    let tag: Tag?
    /// Open Public Polls by followed people instead of the whole feed.
    var following = false
    var header: AnyView?
    @State private var list: CursorList<Poll>?
    @State private var resultsIn: [Poll] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Guests get the login prompt above the topics
                if !app.isSignedIn { LoginPromptCard().pageColumn(560).padding(.top, 8) }
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
        .refreshable { await load(list) }
        .canvas()
        .navigationTitle(tag.map { "#\($0.name)" } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.sessionGeneration) {
            let list = list ?? makeList()
            self.list = list
            await load(list)
        }
    }

    private func load(_ list: CursorList<Poll>?) async {
        async let results: Void = loadResultsIn()
        await list?.reload()
        await results
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
                if !resultsIn.isEmpty { ResultsInCard(polls: resultsIn).padding(.top, 4) }
                if polls.isEmpty {
                    if following { followingEmpty } else { empty }
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

    private var empty: some View {
        EmptyCard(title: app.t(tag == nil ? "homePage.feedListNoData" : "homePage.topicEmpty")) {
            Button(app.t(app.isSignedIn ? "homePage.createFirst" : "homePage.joinToCreate")) { app.openCreator() }
                .buttonStyle(.vm)
        }
    }

    private var followingEmpty: some View {
        EmptyCard(title: app.t("homePage.followingEmpty"), body: app.t("homePage.followingEmptyHint")) {
            Button(app.t("homePage.followingEmptyCta")) { app.select(.explore) }
                .buttonStyle(.vm(.outline))
        }
    }

    /// The whole feed leads, for a signed-in viewer, with Ended Polls they voted in (the web's rail).
    private func loadResultsIn() async {
        guard app.isSignedIn, tag == nil, !following else {
            resultsIn = []
            return
        }
        let ended = (try? await app.service.myPolls(status: .ended, limit: 10).items) ?? []
        resultsIn = Array(app.visible(ended).filter { $0.myOptionId != nil }.prefix(3))
    }

    private func makeList() -> CursorList<Poll> {
        let service = app.service
        if following { return CursorList { cursor in try await service.followingPolls(cursor: cursor, limit: 10) } }
        let slug = tag?.slug
        return CursorList { cursor in try await service.polls(tag: slug, cursor: cursor, limit: 10) }
    }
}

/// "Results are in": Ended Polls the viewer voted in, what each decided, and an unread dot
/// (the web's `PollSideCard kind="resultsIn"`).
private struct ResultsInCard: View {
    @Environment(AppModel.self) private var app
    let polls: [Poll]
    /// Half the title's cap height, so the dot sits mid-line at every text size
    @ScaledMetric(relativeTo: .body) private var dotLift: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.t("homePage.resultsIn").uppercased())
                .font(.vm(13, .semibold, relativeTo: .footnote))
                .tracking(0.78)
                .foregroundStyle(Tokens.mutedForeground)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(polls) { poll in row(poll) }
            }
            .padding(.horizontal, -8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 0)
    }

    private func row(_ poll: Poll) -> some View {
        let unread = poll.unread == true
        return Button { app.push(.poll(poll.id)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                // The dot trails the title, so titles share one left edge whether read or not
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(poll.title)
                        .font(.vm(15, unread ? .semibold : .regular))
                        .tracking(-0.15)
                        .foregroundStyle(Tokens.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if unread {
                        UnreadDot(label: app.t("notifications.unread"))
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotLift }
                    }
                }
                meta(poll).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, minHeight: Metrics.minTarget, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "Yes won · 2,061 voted", or a short "Tie": no room to name every winner.
    private func meta(_ poll: Poll) -> Text {
        let turnout = Text(app.t("poll.voted", ["count": app.t.number(poll.turnout ?? 0)]))
        let separator = Text(verbatim: " · ")
        switch ProfileLists.endedSummary(poll) {
        case let .won(winner):
            let option = Text(winner).font(.vm(13, .medium)).foregroundColor(Tokens.foreground)
            return Text.rich(app.t("profile.wonBy"), ["option": option]) + separator + turnout
        case .tie:
            return Text(app.t("homePage.resultsTie")) + separator + turnout
        case .none:
            return turnout
        }
    }
}

import SwiftUI
import VomattCore

/// Search, filters and topics over Open or Ended Public Polls, listed as tiles to scan (the web's
/// `ExploreView`). Search and filters stay at the top while the grid scrolls; a topic the search
/// found replaces the search.
struct ExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var status = VomattService.ListStatus.open
    @State private var sort = VomattService.ListSort.newest
    /// The picked topic's slug.
    @State private var tag: String?
    @State private var topics: [Tag] = []
    @State private var list: CursorList<Poll>?
    /// A new query's first page is loading; the previous results stay, dimmed, until it arrives
    @State private var isSearching = false
    @State private var gridWidth: CGFloat = 0

    private var apiQuery: ExploreQuery { ExploreQuery(query: query, status: status, sort: sort, tag: tag) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16, pinnedViews: .sectionHeaders) {
                Section {
                    VStack(alignment: .leading, spacing: 16) {
                        topicPills
                        results
                        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !q.isEmpty, q.count < searchMinLength {
                            Text(app.t("explore.searchTooShort")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .pageColumn(Metrics.wideWidth)
                } header: {
                    VStack(alignment: .leading, spacing: 12) {
                        SearchField(placeholder: app.t("explore.searchPlaceholder"), text: $query)
                            .accessibilityLabel(app.t("explore.searchLabel"))
                        filters
                    }
                    .padding(.vertical, 8)
                    .pageColumn(Metrics.wideWidth)
                    .background(Tokens.background)
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await list?.reload() }
        .canvas()
        .navigationTitle(app.t("explore.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { if topics.isEmpty { topics = await app.service.allTags() } }
        .task(id: [AnyHashable(apiQuery), AnyHashable(app.sessionGeneration)]) {
            // Typing waits for a pause
            if list != nil { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            let next = makeList()
            guard list != nil else {
                list = next
                await next.reload()
                return
            }
            isSearching = true
            defer { isSearching = false }
            await next.reload()
            guard !Task.isCancelled else { return }
            list = next
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { statusPills; sortPills }
            VStack(alignment: .leading, spacing: 8) { statusPills; sortPills }
        }
    }

    private func filterRow(_ label: String, @ViewBuilder pills: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.vm(13)).foregroundStyle(Tokens.mutedForeground).accessibilityHidden(true)
            HStack(spacing: 8) { pills() }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(label)
        }
    }

    private var statusPills: some View {
        filterRow(app.t("explore.status")) {
            PillButton(title: app.t("explore.filterActive"), isOn: status == .open) { status = .open }
            PillButton(title: app.t("explore.filterEnded"), isOn: status == .ended) { status = .ended }
        }
    }

    private var sortPills: some View {
        filterRow(app.t("explore.sort")) {
            PillButton(title: app.t("explore.sortNewest"), isOn: sort == .newest) { sort = .newest }
            PillButton(title: app.t("explore.sortEnding"), isOn: sort == .closing) { sort = .closing }
            PillButton(title: app.t("explore.sortTop"), isOn: sort == .top) { sort = .top }
        }
        // Ended Polls take no sort; hidden, not removed, so the list doesn't jump
        .opacity(status == .open ? 1 : 0)
        .disabled(status != .open)
        .accessibilityHidden(status != .open)
    }

    /// The topics the search matches, or the most used; the picked one stays first. Under the bar,
    /// not in it: a fourth stuck row would cover too much of a phone.
    @ViewBuilder private var topicPills: some View {
        let shown = ExploreTopics.shown(topics, q: apiQuery.q, active: tag)
        if !shown.isEmpty {
            HStack(spacing: 16) {
                Text(app.t("explore.topics")).font(.vm(13)).foregroundStyle(Tokens.mutedForeground).accessibilityHidden(true)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shown) { topic in
                            PillButton(title: topic.name, isOn: topic.slug == tag) { pick(topic.slug) }
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(app.t("explore.topics"))
            }
        }
    }

    private func pick(_ slug: String) {
        if slug == tag { tag = nil; return }
        tag = slug
        if apiQuery.q != nil { query = "" }
    }

    @ViewBuilder private var results: some View {
        if let list {
            Group {
                switch list.phase {
                case .idle, .loading:
                    placeholder
                case .failed:
                    LoadFailed(message: app.t("explore.loadFailed")) { await list.reload() }
                case .loaded:
                    let polls = app.visible(list.items)
                    if polls.isEmpty {
                        EmptyCard(title: app.t("explore.noResults"), body: app.t(emptyHint))
                    } else {
                        grid { ForEach(polls) { PollTile(poll: $0) } }
                        if !isSearching { LoadMoreFooter(list: list) }
                    }
                }
            }
            .opacity(isSearching ? 0.5 : 1)
            .allowsHitTesting(!isSearching)
            .animation(.easeOut(duration: 0.15), value: isSearching)
        } else {
            // Before the first list exists is loading too
            placeholder
        }
    }

    /// A topic with no search is what emptied the grid, so it points at the topic.
    private var emptyHint: String {
        if apiQuery.tag != nil, apiQuery.q == nil { return "explore.noResultsHintTopic" }
        return status == .open ? "explore.noResultsHint" : "explore.noResultsHintEnded"
    }

    /// 1 column, 2 from 512pt, 3 from 896pt, by the grid's own width (the web's `PollTileGrid`).
    private func grid(@ViewBuilder content: () -> some View) -> some View {
        let columns = gridWidth >= 896 ? 3 : gridWidth >= 512 ? 2 : 1
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columns), spacing: 16) {
            content()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    private var placeholder: some View {
        grid { ForEach(0..<3, id: \.self) { _ in Skeleton(height: 168, radius: Radius.card) } }
    }

    private func makeList() -> CursorList<Poll> {
        let service = app.service
        let query = apiQuery
        return CursorList { cursor in
            try await service.polls(
                status: query.status, sort: query.sort, tag: query.tag, query: query.q, cursor: cursor, limit: ExploreTopics.pageSize
            )
        }
    }
}

/// A Poll to scan (the web's `PollTile`): its status, the question, its first options (or what it
/// decided) and its turnout. The whole tile opens the poll page, where voting happens; a tile never
/// holds a Ballot, and no option counts show while the Poll is open.
private struct PollTile: View {
    @Environment(AppModel.self) private var app
    let poll: Poll

    private static let previewOptions = 3

    var body: some View {
        let status = poll.status()
        let ended = status == .ended
        Button { app.push(.poll(poll.id)) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    CardStatusChip(poll: poll, status: status)
                    if !ended, poll.myOptionId != nil { VotedPill() }
                }
                Text(poll.title).pollTitle(19).lineLimit(3).multilineTextAlignment(.leading)
                    .accessibilityAddTraits(.isHeader)
                if !ended, !poll.options.isEmpty { optionPreview }
                Spacer(minLength: 0)
                meta(status: status).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card(padding: 20)
            .contentShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
    }

    private var optionPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(poll.options.prefix(Self.previewOptions))) { option in
                HStack(spacing: 8) {
                    Circle().strokeBorder(Tokens.input, lineWidth: 1).frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(option.text).lineLimit(1)
                }
            }
            let hidden = poll.options.count - Self.previewOptions
            if hidden > 0 {
                Text(app.t("explore.moreOptions", ["count": String(hidden)])).padding(.leading, 16)
            }
        }
        .font(.vm(14))
        .foregroundStyle(Tokens.mutedForeground)
    }

    /// What it decided and the turnout once Ended; the turnout while open; nothing for a Scheduled Poll,
    /// which takes no Ballots yet. Then its first two topics.
    private func meta(status: PollStatus) -> Text {
        let turnout = Text(app.t("poll.voted", ["count": app.t.number(poll.turnout ?? 0)])).font(.vmMono(13))
        let separator = Text(verbatim: " · ")
        let lead: Text? = switch status {
        case .ended where poll.isCancelled:
            Text(app.t("notifications.cancelled"))
        case .ended:
            switch ProfileLists.endedSummary(poll) {
            case let .won(winner):
                Text.rich(app.t("profile.wonBy"), ["option": decided(winner)]) + separator + turnout
            case let .tie(winners):
                Text.rich(app.t("profile.tieBetween"), ["options": decided(app.t.list(winners))]) + separator + turnout
            case .none:
                turnout
            }
        case .scheduled:
            nil
        case .open, .closing:
            turnout
        }
        let topics = poll.tags.prefix(2).map(\.name)
        let topicText = topics.isEmpty ? nil : Text(app.t.list(Array(topics)))
        return switch (lead, topicText) {
        case let (lead?, topics?): lead + separator + topics
        case let (lead?, nil): lead
        case let (nil, topics?): topics
        case (nil, nil): Text(verbatim: "")
        }
    }

    private func decided(_ text: String) -> Text {
        Text(text).fontWeight(.medium).foregroundColor(Tokens.foreground)
    }
}

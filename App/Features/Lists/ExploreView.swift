import SwiftUI
import VomattCore

/// Search and filters over Open or Ended Public Polls, plus the popular topics (the web's `ExploreView`).
struct ExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var status = VomattService.ListStatus.open
    @State private var sort = VomattService.ListSort.newest
    @State private var tags: [Tag] = []
    @State private var list: CursorList<Poll>?
    /// A new query's first page is loading; the previous results stay, dimmed, until it arrives
    @State private var isSearching = false

    /// The query sent to the API; ended Polls take no sort, and a 1-character search is no search.
    private var apiKey: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(status)|\(status == .open ? sort.rawValue : "")|\(q.count >= searchMinLength ? q : "")|\(app.sessionGeneration)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(app.t("explore.title")).displayHeading(32).accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 12) {
                    SearchField(placeholder: app.t("explore.searchPlaceholder"), text: $query)
                        .accessibilityLabel(app.t("explore.searchLabel"))
                    filters
                }

                if !tags.isEmpty { topics }

                results
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !q.isEmpty, q.count < searchMinLength {
                    Text(app.t("explore.searchTooShort")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
                        .frame(maxWidth: .infinity)
                }
            }
            .pageColumn(560)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await list?.reload() }
        .canvas()
        .task { if tags.isEmpty { tags = await app.service.popularTags() } }
        .task(id: apiKey) {
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

    private var topics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.t("explore.topics")).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { ForEach(tags) { TopicChip(tag: $0, compact: true) } }
                    .padding(.horizontal, Metrics.gutter)
            }
            .padding(.horizontal, -Metrics.gutter)
        }
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
                        EmptyCard(title: app.t("explore.noResults"),
                                  body: app.t(status == .open ? "explore.noResultsHint" : "explore.noResultsHintEnded"))
                    } else {
                        LazyVStack(spacing: 16) {
                            ForEach(polls) { poll in
                                PollCardView(poll: poll) {
                                    list.update { $0.removeAll { $0.id == poll.id } }
                                }
                            }
                        }
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

    private var placeholder: some View {
        VStack(spacing: 16) { ForEach(0..<3, id: \.self) { index in PollCardSkeleton(options: 3 + index % 2) } }
    }

    private func makeList() -> CursorList<Poll> {
        let service = app.service
        let status = status
        let sort = sort
        let q = query
        return CursorList { cursor in try await service.polls(status: status, sort: sort, query: q, cursor: cursor, limit: 20) }
    }
}

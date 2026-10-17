import SwiftUI
import VomattCore

/// Topics, search and filters over Open or Ended Public Polls (the web's `ExploreView`).
struct ExploreView: View {
    @Environment(AppModel.self) private var app
    @State private var query = ""
    @State private var status = VomattService.ListStatus.open
    @State private var sort = VomattService.ListSort.newest
    @State private var tags: [Tag] = []
    @State private var list: CursorList<Poll>?

    /// The query sent to the API; ended Polls take no sort, and a 1-character search is no search.
    private var apiKey: String {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(status)|\(status == .open ? sort.rawValue : "")|\(q.count >= searchMinLength ? q : "")|\(app.sessionGeneration)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(app.t("explore.title")).displayHeading(32).accessibilityAddTraits(.isHeader)

                if !tags.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(app.t("explore.topics")).font(.vm(14, .semibold))
                        FlowLayout(spacing: 8) { ForEach(tags) { TopicChip(tag: $0) } }
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    SearchField(placeholder: app.t("explore.searchPlaceholder"), text: $query)
                    filters
                    results
                    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !q.isEmpty, q.count < searchMinLength {
                        Text(app.t("explore.searchTooShort")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .pageColumn()
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
            let list = makeList()
            self.list = list
            await list.reload()
        }
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack { statusPills; Spacer(); if status == .open { sortPills } }
            VStack(alignment: .leading, spacing: 8) { statusPills; if status == .open { sortPills } }
        }
    }

    private var statusPills: some View {
        HStack(spacing: 6) {
            PillButton(title: app.t("explore.filterActive"), isOn: status == .open) { status = .open }
            PillButton(title: app.t("explore.filterEnded"), isOn: status == .ended) { status = .ended }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.t("explore.status"))
    }

    private var sortPills: some View {
        HStack(spacing: 6) {
            PillButton(title: app.t("explore.sortNewest"), isOn: sort == .newest) { sort = .newest }
            PillButton(title: app.t("explore.sortEnding"), isOn: sort == .closing) { sort = .closing }
            PillButton(title: app.t("explore.sortTop"), isOn: sort == .top) { sort = .top }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.t("explore.sort"))
    }

    @ViewBuilder private var results: some View {
        if let list {
            switch list.phase {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 48)
            case .failed:
                LoadFailed(message: app.t("explore.loadFailed")) { await list.reload() }
            case .loaded:
                let polls = app.visible(list.items)
                if polls.isEmpty {
                    Text(app.t("explore.noResults")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                        .frame(maxWidth: .infinity).padding(.vertical, 48)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(polls) { poll in
                            PollRow(poll: poll) {
                                Text(app.t("poll.voted", ["count": app.t.number(poll.turnout ?? 0)]))
                                UserChip(username: poll.creatorUsername, avatarUrl: poll.creatorAvatarUrl, avatarSize: 16, link: false)
                            } aside: {
                                StatusChip(poll: poll)
                            }
                        }
                    }
                    LoadMoreFooter(list: list)
                }
            }
        }
    }

    private func makeList() -> CursorList<Poll> {
        let service = app.service
        let status = status
        let sort = sort
        let q = query
        return CursorList { cursor in try await service.polls(status: status, sort: sort, query: q, cursor: cursor, limit: 20) }
    }
}

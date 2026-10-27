import SwiftUI
import VomattCore

/// Active (Scheduled and Open), Drafts and Ended: Polls the user created, voted in or was invited to.
struct MyPollsView: View {
    @Environment(AppModel.self) private var app
    enum Tab: Hashable { case active, drafts, ended }
    @State private var tab = Tab.active
    @State private var open: CursorList<Poll>?
    @State private var ended: CursorList<Poll>?
    @State private var drafts: [PollDraft] = []

    var body: some View {
        Group {
            if app.isSignedIn {
                content
            } else {
                SignedOutPlaceholder(title: app.t("myPolls.title"))
            }
        }
        .canvas()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if app.isSignedIn {
                    Button { app.push(.notifications) } label: {
                        Image(systemName: "bell")
                            .overlay(alignment: .topTrailing) {
                                if let badge = app.unreadBadge { UnreadBadge(count: badge, label: badge, ring: Tokens.background).offset(x: 8, y: -8) }
                            }
                    }
                    .accessibilityLabel(app.t("common.notifications"))
                    .accessibilityValue(app.unreadBadge.map { "\($0) \(app.t("notifications.unread"))" } ?? "")
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(app.t("myPolls.title")).displayHeading(32).accessibilityAddTraits(.isHeader)
                LineTabs(items: [
                    (Tab.active, "\(app.t("myPolls.tabActive")) (\(countLabel(open)))"),
                    (Tab.drafts, app.t("myPolls.tabDrafts")),
                    (Tab.ended, "\(app.t("myPolls.tabEnded")) (\(countLabel(ended)))"),
                ], selection: $tab)
                switch tab {
                case .active: pollList(open)
                case .ended: pollList(ended)
                case .drafts: draftList
                }
            }
            .pageColumn()
            .padding(.vertical, 24)
        }
        .refreshable { await reload() }
        .task(id: app.sessionGeneration) { await reload() }
        .onAppear { drafts = app.drafts.list() }
        .onChange(of: app.creator == nil) { _, closed in if closed { drafts = app.drafts.list() } }
    }

    /// "12", or "12+" while more pages remain.
    private func countLabel(_ list: CursorList<Poll>?) -> String {
        guard let list else { return "0" }
        return "\(list.items.count)\(list.hasMore ? "+" : "")"
    }

    @ViewBuilder private func pollList(_ list: CursorList<Poll>?) -> some View {
        // Before the first page (no list yet, or `.idle`) is loading too, not empty
        if list == nil || list?.phase == .idle || list?.phase == .loading {
            VStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in PollRowSkeleton() } }
        } else if let list, list.phase == .failed {
            LoadFailed(message: app.t("explore.loadFailed")) { await list.reload() }
        } else if let list {
            let polls = app.visible(list.items)
            if polls.isEmpty {
                EmptyState { Text(app.t("myPolls.empty")).frame(maxWidth: .infinity) }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(polls) { poll in
                        PollRow(poll: poll, unread: poll.unread == true) {
                            Text(app.t("poll.voted", ["count": app.t.number(poll.turnout ?? 0)]))
                        } aside: {
                            StatusChip(poll: poll)
                        }
                    }
                }
                LoadMoreFooter(list: list)
            }
        }
    }

    @ViewBuilder private var draftList: some View {
        if drafts.isEmpty {
            EmptyState { Text(app.t("myPolls.empty")).frame(maxWidth: .infinity) }
        } else {
            VStack(spacing: 8) {
                ForEach(drafts) { draft in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(draft.form.title.isEmpty ? app.t("myPolls.untitledDraft") : draft.form.title)
                                .font(.vm(17)).foregroundStyle(Tokens.foreground).lineLimit(2)
                            Text(app.t("myPolls.draftSavedAt", ["date": app.dates.pollDate(draft.savedAt)]))
                                .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(app.t("common.delete")) { drafts = app.drafts.delete(draft.id) }
                            .buttonStyle(.vm(.ghost, size: .sm)).foregroundStyle(Tokens.destructive)
                        Button(app.t("myPolls.draftContinue")) { app.openCreator(draft: draft) }
                            .buttonStyle(.vm(.outline, size: .sm))
                    }
                    .card()
                }
            }
        }
    }

    private func reload() async {
        let service = app.service
        let open = open ?? CursorList { try await service.myPolls(status: .open, cursor: $0) }
        let ended = ended ?? CursorList { try await service.myPolls(status: .ended, cursor: $0) }
        self.open = open
        self.ended = ended
        async let a: Void = open.reload()
        async let b: Void = ended.reload()
        _ = await (a, b)
        await app.refreshUnread()
    }
}

/// What a signed-in-only tab shows to guests.
struct SignedOutPlaceholder: View {
    @Environment(AppModel.self) private var app
    let title: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(title).displayHeading(32)
                LoginPromptCard()
            }
            .pageColumn()
            .padding(.vertical, 24)
        }
    }
}

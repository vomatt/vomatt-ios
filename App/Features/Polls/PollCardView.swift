import SwiftUI
import VomattCore

/// Shows the Ballot until the Poll Ends, then the Results (the web's `PollCard`).
struct PollCardView: View {
    @Environment(AppModel.self) private var app
    let initialPoll: Poll
    /// The detail page: the title isn't a link and the discussion sits below.
    var isDetail = false
    /// Called once the owner Deletes it.
    var onDeleted: (() -> Void)?

    @State private var poll: Poll
    @State private var ballot: BallotModel
    @State private var votersOption: ResultRow?

    init(poll: Poll, isDetail: Bool = false, onDeleted: (() -> Void)? = nil) {
        initialPoll = poll
        self.isDetail = isDetail
        self.onDeleted = onDeleted
        _poll = State(initialValue: poll)
        _ballot = State(initialValue: BallotModel(poll: poll))
    }

    var body: some View {
        // Re-evaluated every minute so the chip and Ballot follow the clock
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(status: poll.status(at: context.date))
        }
        .onChange(of: initialPoll) { _, fresh in apply(fresh) }
        .onChange(of: app.latestPolls[poll.id]) { _, fresh in
            if let fresh, fresh != poll { apply(fresh) }
        }
        .sheet(item: $votersOption) { option in VotersSheet(pollId: poll.id, option: option) }
    }

    private func card(status: PollStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header(status: status)
                titleBlock
                Group {
                    if status == .ended {
                        ResultsView(
                            poll: poll, myOptionId: ballot.myOptionId, turnout: ballot.turnout,
                            onSealed: refetch,
                            onSelectOption: poll.canSeeVoters(viewerId: app.userId) ? { votersOption = $0 } : nil
                        )
                    } else {
                        BallotView(
                            poll: poll, status: status, ballot: ballot,
                            onPollChanged: { changed in
                                // The last Invitee's Ballot can End the Poll
                                if changed.status() == .ended { apply(changed) }
                                app.didUpdate(changed)
                            },
                            onPollEnded: refetch
                        )
                    }
                }
                .id(status == .ended)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: status == .ended)

                if app.userId == poll.creatorId, poll.ownerActions().any {
                    HStack {
                        Spacer()
                        OwnerActionsView(poll: poll, onChanged: refetch, onInviteeCount: { count in
                            poll.inviteeCount = count
                        }, onDeleted: {
                            app.didDelete(poll.id)
                            onDeleted?()
                        })
                    }
                }
            }
            .padding(16)

            footer
        }
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
        .contextMenu {
            ShareLink(item: app.shareURL(for: poll)) { Label(app.t("poll.share"), systemImage: "square.and.arrow.up") }
            ReportButton(subject: "Poll \(poll.id)", url: app.shareURL(for: poll))
            if app.userId != poll.creatorId {
                BlockButton(username: poll.creatorUsername)
            }
        }
    }

    private func header(status: PollStatus) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                UserChip(username: poll.creatorUsername, avatarUrl: poll.creatorAvatarUrl)
                    .font(.vm(13, .medium))
                    .layoutPriority(1)
                Text(app.dates.fromNow(poll.createdAt)).lineLimit(1).fixedSize()
                if let audience = poll.audience, audience != .public {
                    Text("· " + app.t("poll.audience.\(audience.rawValue)")).lineLimit(1).fixedSize()
                }
            }
            .font(.vmMeta)
            .foregroundStyle(Tokens.mutedForeground)
            Spacer(minLength: 0)
            StatusChip(poll: poll)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDetail {
                Text(poll.title).pollTitle().accessibilityAddTraits(.isHeader)
            } else {
                Button { app.push(.poll(poll.id)) } label: {
                    Text(poll.title).pollTitle().multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("poll-title")
            }
            if let description = poll.description, !description.isEmpty {
                Text(description)
                    .font(.vmBody)
                    .foregroundStyle(Tokens.mutedForeground)
                    .lineSpacing(3)
                    .lineLimit(isDetail ? nil : 4)
            }
        }
    }

    /// Turnout, comments and share. Turnout shows in every state.
    private var footer: some View {
        HStack(spacing: 16) {
            if let turnout = ballot.turnout {
                Text(app.t("poll.voted", ["count": app.t.number(turnout)])).font(.vmMono(13))
            }
            if !isDetail {
                Button { app.push(.poll(poll.id)) } label: {
                    Label(commentLabel, systemImage: "bubble.left").labelStyle(.titleAndIcon)
                }
                .frame(minHeight: Metrics.minTarget)
            }
            Spacer()
            ShareLink(item: app.shareURL(for: poll), subject: Text(poll.title)) {
                Label(app.t("poll.share"), systemImage: "square.and.arrow.up")
            }
            .frame(minHeight: Metrics.minTarget)
        }
        .font(.vmMeta)
        .foregroundStyle(Tokens.mutedForeground)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, isDetail ? 4 : 0)
        .frame(minHeight: Metrics.minTarget)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
    }

    private var commentLabel: String {
        guard let count = poll.commentCount else { return app.t("poll.discuss") }
        if count == 0 { return app.t("poll.discuss") }
        return count == 1 ? app.t("poll.comment") : app.t("poll.comments", ["count": count])
    }

    private func apply(_ fresh: Poll) {
        poll = fresh
        ballot.sync(fresh)
    }

    private func refetch() async {
        if let fresh = try? await app.service.poll(id: poll.id) {
            apply(fresh)
            app.didUpdate(fresh)
        }
    }
}

/// Edit, Delete, End now and Invitees for the owner (the web's `OwnerActions`).
struct OwnerActionsView: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    let onChanged: () async -> Void
    let onInviteeCount: (Int) -> Void
    let onDeleted: () -> Void

    enum Confirm: Identifiable { case delete, end; var id: Self { self } }
    @State private var confirming: Confirm?
    @State private var showInvitees = false

    var body: some View {
        let actions = poll.ownerActions()
        HStack(spacing: 6) {
            if actions.canDelete {
                Button(app.t("poll.deletePoll")) { confirming = .delete }
                    .buttonStyle(.vm(.ghost, size: .sm)).foregroundStyle(Tokens.destructive)
            }
            if actions.canEnd {
                Button(app.t("poll.endNow")) { confirming = .end }.buttonStyle(.vm(.outline, size: .sm))
            }
            if actions.canInvite {
                Button(app.t("invitees.title")) { showInvitees = true }.buttonStyle(.vm(.outline, size: .sm))
            }
            if actions.canEdit {
                Button(app.t("poll.edit")) {
                    app.openCreator(poll: poll) { _ in Task { await onChanged() } }
                }
                .buttonStyle(.vm(.outline, size: .sm))
            }
        }
        .alert(
            app.t(confirming == .end ? "poll.endNowTitle" : "poll.deletePollTitle"),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { action in
            Button(app.t("poll.keepPoll"), role: .cancel) {}
            Button(app.t(action == .end ? "poll.endNow" : "poll.deletePoll"), role: action == .delete ? .destructive : nil) {
                Task { action == .delete ? await remove() : await end() }
            }
        } message: { action in
            Text(app.t(action == .end ? "poll.endNowBody" : "poll.deletePollBody"))
        }
        .sheet(isPresented: $showInvitees) {
            InviteeManagerView(pollId: poll.id) { invitees in
                // The Poll Ends once every Invitee holds a Ballot; only then refetch it
                if !invitees.isEmpty, invitees.allSatisfy(\.hasBallot) {
                    Task { await onChanged() }
                } else {
                    onInviteeCount(invitees.count)
                }
            }
        }
    }

    private func remove() async {
        do {
            try await app.service.deletePoll(id: poll.id)
            app.showToast(app.t("poll.deleted"))
            onDeleted()
        } catch {
            // The API explains a passed delete window
            app.showToast((error as? APIError)?.message ?? app.t("poll.deleteFailed"), isError: true)
        }
    }

    private func end() async {
        do {
            try await app.service.closePoll(id: poll.id)
            await onChanged()
        } catch {
            app.showToast((error as? APIError)?.message ?? app.t("poll.endFailed"), isError: true)
        }
    }
}

/// Opens a prefilled email to the team about a Poll or Comment (App Review 1.2: a way to report content).
struct ReportButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    let subject: String
    let url: URL?

    var body: some View {
        if let mail = mailURL {
            Button(role: .destructive) { openURL(mail) } label: {
                Label(app.t("ios.report"), systemImage: "flag")
            }
        }
    }

    private var mailURL: URL? {
        guard !app.config.supportEmail.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = app.config.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "\(app.t("ios.reportSubject")): \(subject)"),
            URLQueryItem(name: "body", value: url?.absoluteString ?? ""),
        ]
        return components.url
    }
}

/// Hides someone's polls and comments on this device.
struct BlockButton: View {
    @Environment(AppModel.self) private var app
    let username: String

    var body: some View {
        Button(role: .destructive) { app.block(username) } label: {
            Label(app.t("ios.block", ["name": username]), systemImage: "hand.raised")
        }
    }
}

/// A compact poll row for lists (the web's `PollListItem`).
struct PollRow<Meta: View, Aside: View>: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    var highlighted = false
    var onOpen: (() -> Void)?
    @ViewBuilder let meta: () -> Meta
    @ViewBuilder let aside: () -> Aside

    var body: some View {
        Button {
            onOpen?()
            app.push(.poll(poll.id))
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    aside()
                    Text(poll.title)
                        .font(.vm(17, relativeTo: .headline))
                        .tracking(-0.17)
                        .foregroundStyle(Tokens.foreground)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 6) { meta() }
                        .font(.vmMeta)
                        .monospacedDigit()
                        .foregroundStyle(Tokens.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.system(size: 14)).foregroundStyle(Tokens.mutedForeground)
            }
            .padding(16)
            .background(Tokens.card, in: RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(highlighted ? Tokens.foreground.opacity(0.4) : Tokens.border))
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
        .buttonStyle(.plain)
    }
}

extension PollRow where Aside == EmptyView {
    init(poll: Poll, highlighted: Bool = false, onOpen: (() -> Void)? = nil, @ViewBuilder meta: @escaping () -> Meta) {
        self.init(poll: poll, highlighted: highlighted, onOpen: onOpen, meta: meta, aside: { EmptyView() })
    }
}

import SwiftUI
import VomattCore

/// Shows the Ballot until the Poll Ends, then the Results (the web's `PollCard`).
struct PollCardView: View {
    @Environment(AppModel.self) private var app
    let initialPoll: Poll
    /// Called once the owner Deletes it.
    var onDeleted: (() -> Void)?

    @State private var poll: Poll
    @State private var ballot: BallotModel
    @State private var votersOption: ResultRow?
    @State private var reporting = false

    init(poll: Poll, onDeleted: (() -> Void)? = nil) {
        initialPoll = poll
        self.onDeleted = onDeleted
        _poll = State(initialValue: poll)
        _ballot = State(initialValue: BallotModel(poll: poll))
    }

    var body: some View {
        // Re-evaluated every minute so the chip and Ballot follow the clock
        TimelineView(.periodic(from: .now, by: 60)) { context in
            card(status: poll.status(at: context.date), now: context.date)
        }
        .onChange(of: initialPoll) { _, fresh in apply(fresh) }
        .onChange(of: app.latestPolls[poll.id]) { _, fresh in
            if let fresh, fresh != poll { apply(fresh) }
        }
        .sheet(item: $votersOption) { option in VotersSheet(pollId: poll.id, option: option) }
        .sheet(isPresented: $reporting) { ReportSheet(pollId: poll.id) }
    }

    private func card(status: PollStatus, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header(status: status, now: now)
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
            .padding(20)

            footer
        }
        .background(Tokens.card, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Tokens.border))
        .contextMenu {
            ShareLink(item: app.shareURL(for: poll)) { Label(app.t("poll.share"), systemImage: "square.and.arrow.up") }
                .simultaneousGesture(TapGesture().onEnded { app.recordShare(of: poll) })
            if app.userId != poll.creatorId {
                ReportPollButton { reporting = true }
                FollowButton(user: UserSummary(id: poll.creatorId, username: poll.creatorUsername, avatarUrl: poll.creatorAvatarUrl))
                BlockButton(username: poll.creatorUsername, userId: poll.creatorId)
            }
        }
    }

    private func header(status: PollStatus, now: Date) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                UserChip(username: poll.creatorUsername, avatarUrl: poll.creatorAvatarUrl, label: "@\(poll.creatorUsername)", avatarSize: 28)
                    .font(.vm(14, .medium))
                    .foregroundStyle(Tokens.foreground)
                    .layoutPriority(1)
                Text("· " + app.dates.age(poll.createdAt, now: now)).lineLimit(1).fixedSize()
                    .font(.vm(14))
                    .foregroundStyle(Tokens.mutedForeground)
            }
            // The handle says whose poll it is; the chip may shorten before it does
            .layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if status != .ended, ballot.myOptionId != nil {
                    VotedPill().transition(.scale(scale: 0.85).combined(with: .opacity))
                }
                CardStatusChip(poll: poll, status: status, now: now)
            }
            .animation(.easeOut(duration: 0.2), value: ballot.myOptionId != nil)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { app.push(.poll(poll.id)) } label: {
                Text(poll.title).pollTitle().multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("poll-title")
            if let description = poll.description, !description.isEmpty {
                Text(description)
                    .font(.vm(16))
                    .foregroundStyle(Tokens.mutedForeground)
                    .lineSpacing(3)
                    .lineLimit(4)
            }
        }
    }

    /// Turnout (and a non-Public Audience), comments, save and share. Turnout shows in every state.
    private var footer: some View {
        HStack(spacing: 20) {
            if !footerMeta.isEmpty {
                Text(footerMeta).font(.vmMono(13)).lineLimit(1)
            }
            Button { app.push(.poll(poll.id)) } label: {
                Label(commentLabel, systemImage: "bubble.left").labelStyle(.titleAndIcon)
            }
            .frame(minHeight: Metrics.minTarget)
            Spacer()
            PollFooterActions(poll: $poll)
        }
        .font(.vm(14))
        .foregroundStyle(Tokens.mutedForeground)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .frame(minHeight: Metrics.minTarget)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
    }

    /// "18 voted · invite only"; a Public Poll says nothing about its Audience.
    private var footerMeta: String {
        [
            ballot.turnout.map { app.t("poll.voted", ["count": app.t.number($0)]) },
            poll.audience.flatMap { $0 == .public ? nil : app.t("poll.audienceMeta.\($0.rawValue)") },
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var commentLabel: String {
        guard let count = poll.commentCount else { return app.t("poll.discuss") }
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
            app.showToast(app.t.message(for: error, fallback: "poll.deleteFailed"), isError: true)
        }
    }

    private func end() async {
        do {
            try await app.service.closePoll(id: poll.id)
            await onChanged()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "poll.endFailed"), isError: true)
        }
    }
}

/// "Report poll" in a poll's menus, for anyone but its owner; signed out, it asks to sign in first.
struct ReportPollButton: View {
    @Environment(AppModel.self) private var app
    let action: () -> Void

    var body: some View {
        Button(role: .destructive) { app.requireAuth(action) } label: {
            Label(app.t("poll.report"), systemImage: "flag")
        }
    }
}

/// Save and Share at the end of a poll's footer (the web's `PollFooter`); on a narrow card they keep
/// only their icons, which still carry their names for VoiceOver.
struct PollFooterActions: View {
    @Environment(AppModel.self) private var app
    @Binding var poll: Poll

    var body: some View {
        ViewThatFits(in: .horizontal) {
            actions.labelStyle(.titleAndIcon)
            actions.labelStyle(.iconOnly)
        }
    }

    private var actions: some View {
        HStack(spacing: 20) {
            BookmarkButton(poll: $poll)
            ShareLink(item: app.shareURL(for: poll), subject: Text(poll.title)) {
                Label(app.t("poll.share"), systemImage: "square.and.arrow.up")
            }
            .frame(minHeight: Metrics.minTarget)
            .simultaneousGesture(TapGesture().onEnded { app.recordShare(of: poll) })
        }
    }
}

/// Saves the poll to the Saved feed, or takes it out: it flips at once and goes back if the request fails.
/// Signed out, it asks to sign in first.
private struct BookmarkButton: View {
    @Environment(AppModel.self) private var app
    @Binding var poll: Poll
    @State private var isSaving = false

    var body: some View {
        let saved = poll.bookmarked == true
        Button { app.requireAuth { Task { await toggle() } } } label: {
            Label(app.t(saved ? "poll.bookmarked" : "poll.bookmark"), systemImage: saved ? "bookmark.fill" : "bookmark")
        }
        .foregroundStyle(saved ? Tokens.foreground : Tokens.mutedForeground)
        .accessibilityAddTraits(saved ? .isSelected : [])
        .frame(minHeight: Metrics.minTarget)
    }

    private func toggle() async {
        guard !isSaving else { return }
        let next = poll.bookmarked != true
        set(next)
        isSaving = true
        defer { isSaving = false }
        do {
            try await app.service.setBookmark(pollId: poll.id, bookmarked: next)
        } catch {
            set(!next)
            app.showToast(app.t.message(for: error, fallback: next ? "poll.bookmarkFailed" : "poll.unbookmarkFailed"), isError: true)
        }
    }

    private func set(_ bookmarked: Bool) {
        poll.bookmarked = bookmarked
        app.didUpdate(poll)
    }
}

/// Follows or unfollows a poll's creator (signed in only); their open public polls show in the Following feed.
struct FollowButton: View {
    @Environment(AppModel.self) private var app
    let user: UserSummary

    var body: some View {
        if app.isSignedIn {
            if app.isFollowing(user.id) {
                Button { app.unfollow(user.id) } label: {
                    Label(app.t("ios.unfollow", ["name": user.username]), systemImage: "person.badge.minus")
                }
            } else {
                Button { app.follow(user) } label: {
                    Label(app.t("ios.follow", ["name": user.username]), systemImage: "person.badge.plus")
                }
            }
        }
    }
}

/// Hides someone's polls and comments; signed in, the API keeps the block.
struct BlockButton: View {
    @Environment(AppModel.self) private var app
    let username: String
    let userId: String?

    var body: some View {
        Button(role: .destructive) { app.blockRequest = .init(username: username, userId: userId) } label: {
            Label(app.t("ios.block", ["name": username]), systemImage: "hand.raised")
        }
    }
}

/// A compact poll row for lists (the web's `PollListItem`).
struct PollRow<Meta: View, Aside: View>: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    var highlighted = false
    /// Bolds the title and puts the unread dot right after it
    var unread = false
    /// The viewer's Ballot on a Poll still open: the Seal and the Tide surface
    var sealed = false
    /// Half the title's cap height, so the dot sits mid-line at every text size
    @ScaledMetric(relativeTo: .headline) private var dotLift: CGFloat = 6
    var onOpen: (() -> Void)?
    @ViewBuilder let meta: () -> Meta
    @ViewBuilder let aside: () -> Aside

    var body: some View {
        Button {
            onOpen?()
            app.push(.poll(poll.id))
        } label: {
            HStack(spacing: 12) {
                if sealed { SealMark(size: 32) }
                VStack(alignment: .leading, spacing: 6) {
                    aside()
                    // The dot trails the title, as it trails a tab's label, so titles keep one left edge read or not.
                    // A view beside the text, not inside it, so truncating a long title never cuts the dot off.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(poll.title)
                            .font(.vm(17, unread ? .semibold : .regular, relativeTo: .headline))
                            .tracking(-0.17)
                            .foregroundStyle(Tokens.foreground)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if unread {
                            // Centered on the first line's capitals, not sat on its baseline
                            UnreadDot(label: app.t("notifications.unread"))
                                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + dotLift }
                        }
                    }
                    HStack(spacing: 6) { meta() }
                        .font(.vmMeta)
                        .monospacedDigit()
                        .foregroundStyle(sealed ? Tokens.tideForeground : Tokens.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.system(size: 14)).foregroundStyle(Tokens.mutedForeground)
            }
            .padding(16)
            .background(sealed ? Tokens.tideTint : Tokens.card, in: RoundedRectangle(cornerRadius: Radius.xl))
            .overlay(RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(highlighted ? Tokens.foreground.opacity(0.4) : sealed ? Tokens.tideLine : Tokens.border))
            .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        }
        .buttonStyle(.plain)
    }
}

extension PollRow where Aside == EmptyView {
    init(
        poll: Poll, highlighted: Bool = false, unread: Bool = false, sealed: Bool = false, onOpen: (() -> Void)? = nil,
        @ViewBuilder meta: @escaping () -> Meta
    ) {
        self.init(poll: poll, highlighted: highlighted, unread: unread, sealed: sealed, onOpen: onOpen, meta: meta, aside: { EmptyView() })
    }
}

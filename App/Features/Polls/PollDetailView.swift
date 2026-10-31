import SwiftUI
import VomattCore

/// `/poll/[id]`: the poll's card, what it promises, a look at the discussion and the author's other polls.
struct PollDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pollId: String

    /// `notFound` carries the owner when the Poll is Invite-only and the viewer can't open it yet.
    enum Phase { case loading, ready(Poll), notFound(PollOwner?), failed }
    @State private var phase = Phase.loading
    @State private var comments: CommentsModel?
    /// The session the comments were loaded in; a sign-in or out reloads them.
    @State private var commentsSession: Int?
    @State private var showDiscussion = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch phase {
                case .loading:
                    PollCardSkeleton(options: 4)
                case let .ready(initial):
                    let poll = app.latest(initial)
                    PollDetailCard(poll: initial, commentCount: comments?.total ?? poll.commentCount) { showDiscussion = true }
                    PollAboutView(poll: poll)
                    if let comments {
                        CommentThreadView(model: comments) { showDiscussion = true }.card(padding: 20)
                    }
                    if poll.status() != .ended { MoreFromAuthorView(poll: poll) }
                case let .notFound(owner):
                    notFound(owner)
                case .failed:
                    LoadFailed(message: app.t("common.error")) { await load() }
                }
            }
            .pageColumn(720)
            .padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let comments, !showDiscussion { ReplyDock(model: comments) }
        }
        .refreshable { await load(reloadComments: true) }
        .canvas()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case let .ready(poll) = phase {
                ToolbarItem(placement: .topBarTrailing) {
                    PollMenu(poll: app.latest(poll), onChanged: refetch) {
                        app.didDelete(poll.id)
                        dismiss()
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showDiscussion) {
            if let comments, case let .ready(poll) = phase {
                PollDiscussionView(model: comments, title: app.latest(poll).title)
            }
        }
        .task(id: "\(pollId)-\(app.sessionGeneration)") { await load() }
    }

    @ViewBuilder private func notFound(_ owner: PollOwner?) -> some View {
        if let owner {
            InvitationPrompt(owner: owner)
        } else if !app.isSignedIn {
            // Signed out, a missing Poll may be Invite-only
            LoginPromptCard(forPoll: true)
        } else {
            EmptyState {
                Text(app.t("pollDetail.notFound")).font(.vm(17, .medium)).foregroundStyle(Tokens.foreground)
                    .accessibilityAddTraits(.isHeader)
                Text(app.t("pollDetail.notFoundBody"))
                Button(app.t("pollDetail.notFoundExplore")) { app.select(.explore) }
                    .buttonStyle(.vm(.outline))
            }
        }
    }

    private func load(reloadComments: Bool = false) async {
        do {
            guard let poll = try await app.service.poll(id: pollId) else {
                phase = .notFound(try? await app.service.inviteOnlyOwner(pollId: pollId))
                return
            }
            let comments = comments ?? CommentsModel(pollId: poll.id, initialTotal: poll.commentCount)
            self.comments = comments
            phase = .ready(poll)
            app.didUpdate(poll)
            if reloadComments || commentsSession != app.sessionGeneration {
                commentsSession = app.sessionGeneration
                await comments.reload(app.service)
            }
            await markReadIfNeeded(poll)
        } catch {
            if case .ready = phase { return }
            phase = .failed
        }
    }

    private func refetch() async {
        if let fresh = try? await app.service.poll(id: pollId) { app.didUpdate(fresh) }
    }

    /// An Invitee has an Invitation until the Poll Ends; then the owner, Participants and
    /// Invitees get the Ended Notification (not for a Cancelled Poll).
    private func markReadIfNeeded(_ poll: Poll) async {
        guard let userId = app.userId else { return }
        let invited = poll.isInvitee(viewerId: userId)
        let hasNotification = poll.status() == .ended
            ? !poll.isCancelled && (poll.creatorId == userId || invited || poll.myOptionId != nil)
            : invited
        guard hasNotification else { return }
        await app.service.markNotificationRead(pollId: poll.id)
        await app.refreshUnread()
    }
}

/// The poll page's card (the web's `PollCard` with `isPage`): the Ballot until the Poll Ends, then
/// the Results, and a footer whose Comments opens the discussion.
private struct PollDetailCard: View {
    @Environment(AppModel.self) private var app
    let initialPoll: Poll
    let commentCount: Int?
    let onOpenDiscussion: () -> Void

    @State private var poll: Poll
    @State private var ballot: BallotModel
    @State private var votersOption: ResultRow?

    init(poll: Poll, commentCount: Int?, onOpenDiscussion: @escaping () -> Void) {
        initialPoll = poll
        self.commentCount = commentCount
        self.onOpenDiscussion = onOpenDiscussion
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
                HStack(spacing: 10) {
                    UserChip(username: poll.creatorUsername, avatarUrl: poll.creatorAvatarUrl, label: "@\(poll.creatorUsername)", avatarSize: 28)
                        .font(.vm(14, .medium))
                        .foregroundStyle(Tokens.foreground)
                        .layoutPriority(1)
                    Text("· " + app.dates.age(poll.createdAt)).lineLimit(1).fixedSize()
                        .font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    Spacer(minLength: 0)
                    CardStatusChip(poll: poll, status: status)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text(poll.title).pollTitle().textSelection(.enabled).accessibilityAddTraits(.isHeader)
                    if let description = poll.description, !description.isEmpty {
                        Text(description).font(.vm(16)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
                    }
                }
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
            }
            .padding(20)

            footer
        }
        .card(padding: nil)
    }

    /// Turnout (and a non-Public Audience), comments, save and share (the web's `PollFooter`). Turnout shows in every state.
    private var footer: some View {
        let meta = [
            ballot.turnout.map { app.t("poll.voted", ["count": app.t.number($0)]) },
            poll.audience.flatMap { $0 == .public ? nil : app.t("poll.audienceMeta.\($0.rawValue)") },
        ].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 20) {
            if !meta.isEmpty { Text(meta).font(.vmMono(13)).monospacedDigit() }
            Button(action: onOpenDiscussion) {
                Label(commentLabel, systemImage: "bubble.left").labelStyle(.titleAndIcon)
            }
            .frame(minHeight: Metrics.minTarget)
            Spacer(minLength: 0)
            PollFooterActions(poll: $poll)
        }
        .font(.vm(14))
        .foregroundStyle(Tokens.mutedForeground)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .overlay(alignment: .top) { Hairline() }
    }

    private var commentLabel: String {
        guard let commentCount else { return app.t("poll.discuss") }
        return commentCount == 1 ? app.t("poll.comment") : app.t("poll.comments", ["count": commentCount])
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

/// The poll page's ••• menu. The owner's controls (the web's `OwnerActions` menu) with Share, destructive
/// ones last; for anyone else Share, Follow, Report and Block.
private struct PollMenu: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    let onChanged: () async -> Void
    let onDeleted: () -> Void

    @State private var pending: OwnerAction?
    @State private var reporting = false

    var body: some View {
        let isOwner = app.userId == poll.creatorId
        let actions = poll.ownerActions()
        Menu {
            if isOwner {
                if actions.canEdit {
                    Button { app.openCreator(poll: poll) { _ in Task { await onChanged() } } } label: {
                        Label(app.t("poll.edit"), systemImage: "pencil")
                    }
                }
                if actions.canEnd {
                    Button { pending = .end } label: { Label(app.t("poll.endNowEllipsis"), systemImage: "stop.circle") }
                }
                if actions.canInvite {
                    Button { pending = .invitees } label: { Label(app.t("invitees.title"), systemImage: "person.2") }
                }
            }
            ShareLink(item: app.shareURL(for: poll), subject: Text(poll.title)) {
                Label(app.t("poll.share"), systemImage: "square.and.arrow.up")
            }
            .simultaneousGesture(TapGesture().onEnded { app.recordShare(of: poll) })
            if isOwner {
                if actions.canDelete {
                    Divider()
                    Button(role: .destructive) { pending = .delete } label: {
                        Label(app.t("poll.deletePollEllipsis"), systemImage: "trash")
                    }
                }
            } else {
                FollowButton(user: UserSummary(id: poll.creatorId, username: poll.creatorUsername, avatarUrl: poll.creatorAvatarUrl))
                ReportPollButton { reporting = true }
                BlockButton(username: poll.creatorUsername, userId: poll.creatorId)
            }
        } label: {
            Image(systemName: "ellipsis").frame(width: Metrics.minTarget, height: Metrics.minTarget)
        }
        .accessibilityLabel(app.t("poll.moreActions", ["title": poll.title]))
        .sheet(isPresented: $reporting) { ReportSheet(pollId: poll.id) }
        .ownerActionFlows($pending, poll: poll, onChanged: onChanged, onInviteeCount: { count in
            var changed = poll
            changed.inviteeCount = count
            app.didUpdate(changed)
        }, onDeleted: onDeleted)
    }
}

/// The voting window, the rules and topics; once Ended, one line (the web's `PollAbout`).
struct PollAboutView: View {
    @Environment(AppModel.self) private var app
    let poll: Poll

    var body: some View {
        let status = poll.status()
        VStack(alignment: .leading, spacing: 16) {
            RailHeading(text: app.t("pollDetail.about"))
            if status == .ended {
                Group {
                    if poll.endedEarly, let deadline = poll.deadline {
                        Text(app.t("pollDetail.endedEarly", ["date": app.dates.pollDate(deadline)]))
                    } else {
                        Text(app.t("pollDetail.resultsIn"))
                    }
                }
                .font(.vm(14)).foregroundStyle(Tokens.foreground)
            } else {
                VStack(spacing: 8) {
                    dateRow(app.t(status == .scheduled ? "pollDetail.opens" : "pollDetail.opened"), app.dates.pollDate(poll.startTime))
                    if let progress = poll.timelineProgress() {
                        ProgressView(value: progress.rounded(), total: 100)
                            .progressViewStyle(TimelineStyle())
                            .accessibilityLabel(app.t("pollDetail.timeline"))
                    }
                    dateRow(app.t("pollDetail.results"), poll.endTime.map { app.dates.pollDate($0) }, fallback: app.t("pollDetail.noEnd"))
                }
                .font(.vmMeta)

                VStack(alignment: .leading, spacing: 10) {
                    rule("lock", app.t("pollDetail.ruleSealed"))
                    rule("person", app.t("pollDetail.ruleOneVote"))
                    if let level = poll.visibilityLevel { rule("eye", app.t("poll.visibility.\(level.rawValue)")) }
                }
                .font(.vm(14))
                .lineSpacing(3)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .tidePanel()

                if !poll.tags.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(poll.tags) { tag in
                            Button { app.push(.topic(tag)) } label: {
                                Text(tag.name)
                                    .font(.vm(12, .medium))
                                    .foregroundStyle(Tokens.foreground)
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Tokens.field, in: Capsule())
                                    // A 44pt tall hit area; the row spacing keeps each chip's its own
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, -8)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(app.t("pollDetail.topics"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private func dateRow(_ label: String, _ value: String?, fallback: String = "") -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(Tokens.mutedForeground)
            Spacer(minLength: 0)
            Text(value ?? fallback).font(value == nil ? .vmMeta : .vmMono(13)).foregroundStyle(Tokens.foreground)
        }
        .accessibilityElement(children: .combine)
    }

    private func rule(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Tokens.tide).frame(width: 16).accessibilityHidden(true)
            Text(text).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Two of the author's other Polls, while this one is open (the web's `MoreFromAuthor`); left out when
/// there are none or the list fails.
private struct MoreFromAuthorView: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    @State private var polls: [Poll] = []

    var body: some View {
        Group {
            if !polls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    RailHeading(text: app.t("pollDetail.moreFrom", ["username": poll.creatorUsername]))
                    VStack(spacing: 0) {
                        ForEach(app.visible(polls)) { other in
                            Button { app.push(.poll(other.id)) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(other.title)
                                        .font(.vm(15, .medium)).tracking(-0.15)
                                        .foregroundStyle(Tokens.foreground)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(MoreFromAuthor.meta(other, t: app.t, dates: app.dates))
                                        .font(.vmMono(13)).monospacedDigit()
                                        .foregroundStyle(Tokens.mutedForeground)
                                }
                                .frame(maxWidth: .infinity, minHeight: Metrics.minTarget, alignment: .leading)
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .card(padding: 20)
            }
        }
        .task(id: poll.id) {
            let page = try? await app.service.userPolls(username: poll.creatorUsername, limit: 3)
            polls = MoreFromAuthor.pick(page?.items ?? [], excluding: poll.id)
        }
    }
}

/// An Invitation link to an Invite-only Poll the viewer can't open yet (the web's `InvitationPrompt`).
private struct InvitationPrompt: View {
    @Environment(AppModel.self) private var app
    let owner: PollOwner

    var body: some View {
        VStack(spacing: 12) {
            AvatarView(username: owner.username, avatarUrl: owner.avatarUrl, size: 56)
            Text(app.t("poll.invitation.title", ["username": owner.username]))
                .pollTitle(25)
                .accessibilityAddTraits(.isHeader)
            Text(app.t(app.isSignedIn ? "poll.invitation.wrongAccount" : "poll.invitation.signIn"))
                .font(.vm(16)).foregroundStyle(Tokens.mutedForeground)
            Label {
                Text(app.t("poll.audience.invite-only"))
            } icon: {
                Image(systemName: "lock").foregroundStyle(Tokens.tide)
            }
            .font(.vm(12, .medium))
            .foregroundStyle(Tokens.foreground)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Tokens.field, in: Capsule())
            Group {
                if app.isSignedIn {
                    LoadingButton(style: .vm(.outline), action: switchAccount) { Text(app.t("poll.invitation.switchAccount")) }
                } else {
                    Button(app.t("loginPrompt.ctaLabel")) { app.signIn() }.buttonStyle(.vm(.default))
                }
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .card(padding: nil)
    }

    /// Signs out and back in, for the account the invitation was sent to.
    private func switchAccount() async {
        await app.signOut()
        app.signIn()
    }
}

/// The thin voting-window bar.
struct TimelineStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.muted)
                Capsule().fill(Tokens.tide).frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 6)
    }
}

/// Wraps its children onto new lines (`flex-wrap`).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var y: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > maxWidth {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// "Log in or sign up for Vomatt" (the web's `LoginPrompt`).
struct LoginPromptCard: View {
    @Environment(AppModel.self) private var app
    /// Adds that logging in opens this Poll.
    var forPoll = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app.t("loginPrompt.title")).font(.vm(14, .semibold)).foregroundStyle(Tokens.foreground)
            Text(app.t("loginPrompt.subtitle") + (forPoll ? " " + app.t("loginPrompt.pollNote") : ""))
                .font(.vm(14)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
            Button(app.t("loginPrompt.ctaLabel")) { app.signIn() }
                .buttonStyle(.vm(.default, size: .sm, fullWidth: true))
                .padding(.top, 10)
        }
        .card(padding: 20)
    }
}

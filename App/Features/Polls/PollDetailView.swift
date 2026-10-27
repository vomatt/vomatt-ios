import SwiftUI
import VomattCore

/// `/poll/[id]`: the card, who asked and when, and the discussion.
struct PollDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pollId: String

    /// `notFound` carries the owner when the Poll is Invite-only and the viewer can't open it yet.
    enum Phase { case loading, ready(Poll), notFound(PollOwner?), failed }
    @State private var phase = Phase.loading
    @State private var comments: CommentsModel?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch phase {
                case .loading:
                    PollCardSkeleton(options: 4)
                case let .ready(poll):
                    PollCardView(poll: poll, isDetail: true) { dismiss() }
                    PollAboutView(poll: app.latest(poll))
                    if let comments { CommentThreadView(model: comments).card(padding: nil) }
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
            if let comments { ReplyDock(model: comments) }
        }
        .refreshable { await load() }
        .canvas()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(pollId)-\(app.sessionGeneration)") { await load() }
    }

    @ViewBuilder private func notFound(_ owner: PollOwner?) -> some View {
        if let owner {
            UserChip(username: owner.username, avatarUrl: owner.avatarUrl,
                     label: app.t("ios.invitedBy", ["name": owner.username]), avatarSize: 28, link: false)
                .font(.vm(15, .semibold))
                .foregroundStyle(Tokens.foreground)
        }
        // Signed out, a missing Poll may be Invite-only (e.g. from an invitation email)
        if !app.isSignedIn {
            LoginPromptCard()
        } else if let owner {
            EmptyState { Text(app.t("ios.inviteOnlyOtherAccount", ["name": owner.username])) }
        } else {
            EmptyState { Text(app.t("pollDetail.notFound")) }
        }
    }

    private func load() async {
        do {
            guard let poll = try await app.service.poll(id: pollId) else {
                phase = .notFound(try? await app.service.inviteOnlyOwner(pollId: pollId))
                return
            }
            if comments == nil { comments = CommentsModel(pollId: poll.id, initialTotal: poll.commentCount) }
            phase = .ready(poll)
            app.didUpdate(poll)
            await markReadIfNeeded(poll)
        } catch {
            if case .ready = phase { return }
            phase = .failed
        }
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

/// Who asked, the voting window, turnout and topics (the web's `PollAbout`).
struct PollAboutView: View {
    @Environment(AppModel.self) private var app
    let poll: Poll

    var body: some View {
        let status = poll.status()
        VStack(alignment: .leading, spacing: 20) {
            Button { app.push(.profile(poll.creatorUsername)) } label: {
                HStack(spacing: 12) {
                    AvatarView(username: poll.creatorUsername, avatarUrl: poll.creatorAvatarUrl, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.t("pollDetail.askedBy")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
                        Text(poll.creatorUsername).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
                    }
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(app.t("pollDetail.opened", ["date": app.dates.pollDate(poll.startTime)]))
                    Spacer()
                    if let endTime = poll.endTime { Text(app.dates.pollDate(endTime)) }
                }
                .font(.vm(12))
                .foregroundStyle(Tokens.mutedForeground)
                if let progress = poll.timelineProgress() {
                    ProgressView(value: progress, total: 100)
                        .progressViewStyle(TimelineStyle())
                        .accessibilityLabel(app.t("pollDetail.timeline"))
                }
                Text(statusLine(status)).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
            }

            if let turnout = poll.turnout {
                (Text(app.t.number(turnout)).font(.vmMono(30)).tracking(-0.5).foregroundStyle(Tokens.foreground)
                    + Text(" " + app.t("pollDetail.participants")
                        + (poll.inviteeCount.map { " · " + app.t("pollDetail.invited", ["count": app.t.number($0)]) } ?? ""))
                    .font(.vm(14)).foregroundStyle(Tokens.mutedForeground))
            }

            if let audience = poll.audience, audience != .public {
                (Text(app.t("poll.audience.\(audience.rawValue)")).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
                    + Text(" · " + app.t("pollDetail.audience.\(audience.rawValue)")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground))
                    .lineSpacing(3)
            }

            if !poll.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(poll.tags) { tag in TopicChip(tag: tag, compact: true) }
                }
                .accessibilityLabel(app.t("pollDetail.topics"))
            }

            if status != .ended {
                Text(app.t("pollDetail.sealedExplainer")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
            }

            ShareLink(item: app.shareURL(for: poll), subject: Text(poll.title)) {
                Label(app.t(poll.audience == .inviteOnly ? "poll.share" : "pollDetail.shareCta"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.vm(.outline, size: .sm, fullWidth: true))
            .simultaneousGesture(TapGesture().onEnded { app.recordShare(of: poll) })
        }
        .card(padding: 20)
    }

    private func statusLine(_ status: PollStatus) -> String {
        switch status {
        case .ended:
            if poll.endedEarly, let deadline = poll.deadline {
                return app.t("pollDetail.endedEarly", ["date": app.dates.pollDate(deadline)])
            }
            return app.t("pollDetail.resultsIn")
        case .scheduled:
            return app.t("poll.opensHint", ["distance": app.dates.fromNow(poll.startTime)])
        default:
            guard let endTime = poll.endTime else { return app.t("pollDetail.noEnd") }
            return app.t("pollDetail.revealsIn", ["distance": app.dates.fromNow(endTime)])
        }
    }
}

/// The thin voting-window bar.
struct TimelineStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.muted)
                Capsule().fill(Tokens.primary).frame(width: proxy.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 6)
    }
}

/// `#topic`, linking to its feed.
struct TopicChip: View {
    @Environment(AppModel.self) private var app
    let tag: Tag
    var compact = false

    var body: some View {
        Button { app.push(.topic(tag)) } label: {
            HStack(spacing: 8) {
                Text("#\(tag.name)")
                if !compact, let count = tag.usageCount {
                    Text("\(count)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                }
            }
            .font(.vm(compact ? 13 : 14))
            .foregroundStyle(Tokens.foreground)
            .padding(.horizontal, compact ? 12 : 14)
            .frame(minHeight: compact ? 32 : 40)
            .background(Tokens.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app.t("loginPrompt.title")).font(.vm(14, .semibold)).foregroundStyle(Tokens.foreground)
            Text(app.t("loginPrompt.subtitle")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
            Button(app.t("loginPrompt.ctaLabel")) { app.signIn() }
                .buttonStyle(.vm(.default, size: .sm, fullWidth: true))
                .padding(.top, 10)
        }
        .card(padding: 20)
    }
}

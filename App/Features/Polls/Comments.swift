import Observation
import SwiftUI
import VomattCore

/// Comments on one Poll, newest first, with one level of Replies loaded on demand,
/// optimistic posting and likes (the web's `useComments`).
@Observable
final class CommentsModel {
    struct ReplyTarget: Equatable {
        let comment: Comment
        var rootId: String { comment.parentId ?? comment.id }
        /// A Reply to a Reply addresses its author; the API files both under the top-level Comment.
        var prefix: String { comment.parentId != nil ? Comment.replyPrefix(to: comment.author ?? "") : "" }
    }

    enum Status { case loading, ready, error }

    struct ReplyList {
        var items: [Comment] = []
        var nextCursor: String?
        var status: Status = .ready
    }

    let pollId: String
    private(set) var comments: [Comment] = []
    private(set) var replies: [String: ReplyList] = [:]
    private(set) var total: Int?
    private(set) var status = Status.loading
    private(set) var isLoadingMore = false
    /// What the docked composer answers; nil while it is closed.
    var replyTarget: ReplyTarget?
    private var nextCursor: String?
    var hasMore: Bool { nextCursor != nil }

    init(pollId: String, initialTotal: Int?) {
        self.pollId = pollId
        total = initialTotal
    }

    func reload(_ service: VomattService) async {
        status = .loading
        replyTarget = nil
        do {
            let page = try await service.comments(pollId: pollId)
            comments = page.items
            replies = [:]
            seedReplies(page.items)
            nextCursor = page.nextCursor
            status = .ready
        } catch {
            status = .error
        }
    }

    func loadMore(_ service: VomattService) async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await service.comments(pollId: pollId, cursor: cursor) else { return }
        comments = mergeById(comments, page.items)
        seedReplies(page.items)
        nextCursor = page.nextCursor
    }

    /// The list carries each Comment's first Replies; "Show more" continues after them.
    private func seedReplies(_ page: [Comment]) {
        for comment in page where !comment.replies.isEmpty && replies[comment.id] == nil {
            replies[comment.id] = ReplyList(items: comment.replies, nextCursor: comment.repliesNextCursor)
        }
    }

    /// First call loads the Replies; later calls load the next page.
    func loadReplies(_ rootId: String, _ service: VomattService) async {
        let current = replies[rootId]
        if current?.status == .loading { return }
        // Loaded to the end; a failed page is retried from where it stopped
        if let current, current.status != .error, current.nextCursor == nil { return }
        replies[rootId, default: ReplyList()].status = .loading
        do {
            let page = try await service.replies(pollId: pollId, commentId: rootId, cursor: current?.nextCursor)
            replies[rootId]?.items = mergeById(replies[rootId]?.items ?? [], page.items)
            replies[rootId]?.nextCursor = page.nextCursor
            replies[rootId]?.status = .ready
        } catch {
            replies[rootId]?.status = .error
        }
    }

    /// Shows the Comment at once as pending, then swaps in the saved one.
    func add(_ text: String, author: String, avatarUrl: String?, rootId: String?, _ service: VomattService) async throws {
        let tempId = "pending-\(UUID().uuidString)"
        let pending = Comment(id: tempId, author: author, authorAvatarUrl: avatarUrl, text: text, createdAt: .now, parentId: rootId)
        // Replies read oldest first, top-level Comments newest first
        if let rootId {
            replies[rootId, default: ReplyList()].items.append(pending)
            shiftReplyCount(rootId, by: 1)
        } else {
            comments.insert(pending, at: 0)
        }
        total = shiftCount(total, by: 1)

        do {
            let saved = try await service.postComment(pollId: pollId, text: text, parentId: rootId)
            replace(tempId) { _ in saved }
        } catch {
            if let rootId {
                replies[rootId]?.items.removeAll { $0.id == tempId }
                shiftReplyCount(rootId, by: -1)
            } else {
                comments.removeAll { $0.id == tempId }
            }
            total = shiftCount(total, by: -1)
            throw error
        }
    }

    func reply(_ body: String, to target: ReplyTarget, author: String, avatarUrl: String?, _ service: VomattService) async throws {
        let rootId = target.rootId
        // Show the thread the Reply lands in
        if replies[rootId] == nil, comments.contains(where: { $0.id == rootId && $0.replyCount > 0 }) {
            await loadReplies(rootId, service)
        }
        try await add(target.prefix + body, author: author, avatarUrl: avatarUrl, rootId: rootId, service)
    }

    func edit(_ commentId: String, text: String, _ service: VomattService) async throws {
        let saved = try await service.updateComment(pollId: pollId, commentId: commentId, text: text)
        replace(commentId) { _ in saved }
    }

    /// A top-level Comment with Replies becomes a placeholder; anything else leaves the list.
    func remove(_ comment: Comment, _ service: VomattService) async throws {
        try await service.deleteComment(pollId: pollId, commentId: comment.id)
        // The dock can't answer a Comment that is gone, or one in a thread that is
        defer {
            if let target = replyTarget, target.comment.id == comment.id || target.rootId == comment.id
                || !comments.contains(where: { $0.id == target.rootId }) {
                replyTarget = nil
            }
        }
        total = shiftCount(total, by: -1)
        guard let rootId = comment.parentId else {
            if comment.replyCount > 0 {
                replace(comment.id) { c in
                    var placeholder = c
                    placeholder.deleted = true
                    placeholder.author = nil
                    placeholder.text = nil
                    placeholder.userId = nil
                    return placeholder
                }
            } else {
                comments.removeAll { $0.id == comment.id }
            }
            return
        }
        replies[rootId]?.items.removeAll { $0.id == comment.id }
        shiftReplyCount(rootId, by: -1)
        // A placeholder with no Replies left isn't listed by the API either
        comments.removeAll { $0.id == rootId && $0.deleted && $0.replyCount == 0 }
    }

    func toggleLike(_ comment: Comment, _ service: VomattService) async {
        let liked = !comment.likedByCurrentUser
        let apply: (Bool) -> Void = { isLiked in
            self.replace(comment.id) { c in
                var c = c
                c.likedByCurrentUser = isLiked
                c.likeCount = max(0, c.likeCount + (isLiked ? 1 : -1))
                return c
            }
        }
        apply(liked)
        do {
            try await service.setLike(pollId: pollId, commentId: comment.id, liked: liked)
        } catch {
            apply(!liked)
        }
    }

    private func shiftReplyCount(_ rootId: String, by delta: Int) {
        replace(rootId) { c in
            var c = c
            c.replyCount = max(0, c.replyCount + delta)
            return c
        }
    }

    /// Applies `change` to the Comment or Reply with this id, wherever it is.
    private func replace(_ id: String, _ change: (Comment) -> Comment) {
        comments = comments.map { $0.id == id ? change($0) : $0 }
        if let target = replyTarget, target.comment.id == id { replyTarget = ReplyTarget(comment: change(target.comment)) }
        // One read, one write: an in-place `replies[key]?.items = …` overlaps its own read
        guard let key = replies.first(where: { $0.value.items.contains { $0.id == id } })?.key, var list = replies[key] else { return }
        list.items = list.items.map { $0.id == id ? change($0) : $0 }
        replies[key] = list
    }
}

/// The discussion under a Poll. Results stay sealed while it is open, so this is where people argue their case.
/// The screen owns the model so `ReplyDock` can sit above the keyboard.
struct CommentThreadView: View {
    @Environment(AppModel.self) private var app
    let model: CommentsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionTitle(text: app.t("comments.title"))
                if let total = model.total {
                    Text("\(total)").font(.vmMono(13)).foregroundStyle(Tokens.mutedForeground)
                }
            }
            CommentComposer(placeholder: app.t("comments.placeholder")) { text in
                do {
                    try await model.add(text, author: app.me?.username ?? app.t("comments.you"),
                                        avatarUrl: app.me?.avatarUrl, rootId: nil, app.service)
                    return true
                } catch {
                    app.showToast(app.t.message(for: error, fallback: "comments.postFailed"), isError: true)
                    return false
                }
            }

            switch model.status {
            case .loading:
                VStack(spacing: 12) { Skeleton(height: 48, radius: Radius.lg); Skeleton(height: 48, radius: Radius.lg) }
            case .error:
                HStack(spacing: 4) {
                    Text(app.t("comments.loadFailed"))
                    Button(app.t("comments.retry")) { Task { await model.reload(app.service) } }.underline()
                }
                .font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            case .ready:
                if model.comments.isEmpty {
                    Text(app.t("comments.empty")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                }
            }

            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(model.comments.filter { !app.isBlocked($0.author) }) { comment in
                    CommentItemView(comment: comment, model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.comments.map(\.id))

            if model.hasMore {
                LoadingButton(style: .vm(.ghost, size: .sm, fullWidth: true), action: { await model.loadMore(app.service) }) {
                    Text(app.t("comments.loadMore")).foregroundStyle(Tokens.mutedForeground)
                }
            }
        }
        .padding(20)
        .task(id: app.sessionGeneration) { await model.reload(app.service) }
    }
}

/// A top-level Comment with its Replies hung off its avatar rail.
private struct CommentItemView: View {
    @Environment(AppModel.self) private var app
    let comment: Comment
    let model: CommentsModel

    var body: some View {
        let replyList = model.replies[comment.id]
        let replies = (replyList?.items ?? []).filter { !app.isBlocked($0.author) }
        let loading = replyList?.status == .loading
        let action = repliesAction(replyList)
        let hasRail = !replies.isEmpty || loading || action != nil
        VStack(alignment: .leading, spacing: 0) {
            CommentRow(comment: comment, model: model, rail: hasRail ? .root : .none)
            ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                CommentRow(comment: reply, model: model,
                           rail: .reply(continues: index < replies.count - 1 || loading || action != nil))
            }
            if loading {
                RailRow(continues: action != nil) { Skeleton(height: 40, radius: Radius.lg).padding(.vertical, 6) }
            }
            if let action {
                RailRow(continues: false) {
                    Button(action) { Task { await model.loadReplies(comment.id, app.service) } }
                        .font(.vm(13, .medium)).foregroundStyle(Tokens.mutedForeground)
                        .frame(minHeight: 36)
                        .padding(.top, 2)
                }
            }
        }
    }

    /// One button walks the Replies: view them, retry a failed page, or load more.
    private func repliesAction(_ list: CommentsModel.ReplyList?) -> String? {
        guard let list else {
            guard comment.replyCount > 0 else { return nil }
            return app.t(comment.replyCount == 1 ? "comments.viewReply" : "comments.viewReplies", ["count": comment.replyCount])
        }
        if list.status == .error { return app.t("comments.retry") }
        if list.status == .ready, list.nextCursor != nil {
            let more = max(1, comment.replyCount - list.items.count)
            return app.t(more == 1 ? "comments.moreReply" : "comments.moreReplies", ["count": more])
        }
        return nil
    }
}

/// The rail: a 2pt line down from the avatar, and an elbow into each Reply.
private nonisolated enum Rail {
    case none
    case root
    case reply(continues: Bool)

    static let width: CGFloat = 32
    static let line: CGFloat = 2
}

/// The gutter beside a Reply (or a row of Replies): the elbow, and the line on to the next one.
private struct RailGutter: View {
    let continues: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if continues {
                Rectangle().fill(Tokens.border).frame(width: Rail.line).frame(maxHeight: .infinity)
                    .offset(x: Rail.width / 2 - Rail.line / 2)
            }
            ElbowShape().stroke(Tokens.border, style: StrokeStyle(lineWidth: Rail.line, lineCap: .round))
                .frame(width: 28, height: 18)
                .offset(x: Rail.width / 2 - Rail.line / 2, y: -2)
        }
        .frame(width: Rail.width)
        .accessibilityHidden(true)
    }
}

/// Something that hangs off the rail after the Replies: a skeleton, or "View n replies".
private struct RailRow<Content: View>: View {
    let continues: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RailGutter(continues: continues)
            content()
        }
    }
}

/// Down from the rail, then a rounded turn to the right.
private nonisolated struct ElbowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let x = rect.minX + Rail.line / 2
        let corner = min(12, rect.height)
        p.move(to: CGPoint(x: x, y: rect.minY))
        p.addLine(to: CGPoint(x: x, y: rect.maxY - corner))
        p.addQuadCurve(to: CGPoint(x: x + corner, y: rect.maxY), control: CGPoint(x: x, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}

/// One Comment or Reply: avatar, meta, text and its action pills. Long-press for the same menu as "…".
private struct CommentRow: View {
    @Environment(AppModel.self) private var app
    let comment: Comment
    let model: CommentsModel
    let rail: Rail

    @State private var isEditing = false
    @State private var draft = ""
    @State private var confirmingDelete = false
    @State private var reporting = false

    private var isReply: Bool { if case .reply = rail { return true } else { return false } }
    private var avatarSize: CGFloat { isReply ? 24 : 32 }
    private var isOwn: Bool { app.userId != nil && comment.userId == app.userId }
    private var isTarget: Bool { model.replyTarget?.comment.id == comment.id }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            switch rail {
            case .none, .root:
                VStack(spacing: 6) {
                    avatar
                    if case .root = rail {
                        Rectangle().fill(Tokens.border).frame(width: Rail.line).frame(maxHeight: .infinity)
                    }
                }
                .frame(width: Rail.width)
            case let .reply(continues):
                RailGutter(continues: continues)
                avatar.padding(.top, 4)
            }

            if comment.deleted || comment.author == nil {
                Text(app.t("comments.deleted"))
                    .font(.vm(14)).italic().foregroundStyle(Tokens.mutedForeground)
                    .frame(minHeight: avatarSize)
                    .padding(.top, isReply ? 4 : 0)
                    .padding(.bottom, 6)
            } else {
                content(author: comment.author ?? "")
                    .padding(.top, isReply ? 6 : 0)
                    .padding(.bottom, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var avatar: some View {
        if comment.deleted || comment.author == nil {
            Circle().strokeBorder(Tokens.borderStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .frame(width: avatarSize, height: avatarSize)
                .accessibilityHidden(true)
        } else {
            let author = comment.author ?? ""
            Button { app.push(.profile(author)) } label: {
                AvatarView(username: author, avatarUrl: comment.authorAvatarUrl, size: avatarSize)
            }
            .buttonStyle(.plain)
            .disabled(comment.isPending)
            .accessibilityHidden(true)
        }
    }

    private func content(author: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(author) { app.push(.profile(author)) }
                    .font(.vm(13, .medium)).foregroundStyle(Tokens.foreground)
                    .disabled(comment.isPending)
                if isOwn { Chip(text: app.t("comments.you"), tint: Tokens.highlight) }
                if isEditing {
                    Text(app.t("ios.editing"))
                } else {
                    Text(app.dates.fromNow(comment.createdAt)).font(.vmMono(12))
                    if comment.edited { Text(app.t("comments.edited")) }
                }
            }
            .font(.vm(12))
            .foregroundStyle(Tokens.mutedForeground)

            if let addressee = comment.addressee, !isEditing {
                HStack(spacing: 5) {
                    Image(systemName: "arrowshape.turn.up.left").font(.system(size: 10, weight: .bold))
                    Text(addressee)
                }
                .font(.vm(12, .medium))
                .foregroundStyle(Tokens.mutedForeground)
                .padding(.leading, 6).padding(.trailing, 8)
                .frame(height: 22)
                .overlay(Capsule().strokeBorder(Tokens.borderStrong, lineWidth: 1))
                .accessibilityLabel(app.t("ios.replyingTo", ["name": addressee]))
            }

            if isEditing {
                VMTextEditor(placeholder: app.t("comments.edit"), text: $draft, minHeight: 80, font: .vm(16), autoFocus: true)
                HStack(spacing: 8) {
                    Text("\(draft.count) / \(commentMax)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                    Spacer()
                    Button(app.t("common.cancel")) { isEditing = false }.buttonStyle(.vm(.ghost, size: .sm))
                    LoadingButton(style: .vm(.default, size: .sm), action: saveEdit) { Text(app.t("common.save")) }
                        .disabled(draft.count > commentMax)
                }
            } else {
                Text(comment.bodyText ?? "")
                    .font(.vm(15))
                    .foregroundStyle(Tokens.foreground)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !comment.isPending, !isEditing { actions }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isTarget ? Tokens.highlightTint : .clear, in: RoundedRectangle(cornerRadius: Radius.xl))
        .padding(.horizontal, -8).padding(.vertical, -4)
        .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        .contextMenu { if !comment.isPending, !isEditing { menuItems } }
        .opacity(comment.isPending ? 0.6 : 1)
        .animation(.easeOut(duration: 0.15), value: isTarget)
        .sheet(isPresented: $confirmingDelete) { DeleteCommentSheet(comment: comment, model: model) }
        .sheet(isPresented: $reporting) { ReportSheet(title: app.t("ios.reportCommentTitle"), message: app.t("ios.reportCommentBody")) { reason, note in
                try await app.service.reportComment(pollId: model.pollId, commentId: comment.id, reason: reason, note: note)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 2) {
            Button {
                app.requireAuth { Task { await model.toggleLike(comment, app.service) } }
            } label: {
                Image(systemName: comment.likedByCurrentUser ? "heart.fill" : "heart")
                    .font(.system(size: 15))
                    .symbolEffect(.bounce, value: comment.likedByCurrentUser)
                if comment.likeCount > 0 { Text("\(comment.likeCount)").font(.vmMono(13)) }
            }
            .buttonStyle(ActionPillStyle(isOn: comment.likedByCurrentUser))
            .accessibilityLabel(app.t("comments.like"))
            .accessibilityValue("\(comment.likeCount)")
            .accessibilityAddTraits(comment.likedByCurrentUser ? .isSelected : [])

            Button {
                app.requireAuth { model.replyTarget = isTarget ? nil : .init(comment: comment) }
            } label: {
                Image(systemName: "arrowshape.turn.up.left").font(.system(size: 14, weight: isTarget ? .semibold : .regular))
                Text(app.t(isTarget ? "ios.replying" : "comments.reply"))
            }
            .buttonStyle(ActionPillStyle(isOn: isTarget, tinted: false))
            .accessibilityAddTraits(isTarget ? .isSelected : [])

            Spacer(minLength: 0)

            Menu { menuItems } label: {
                Image(systemName: "ellipsis").font(.system(size: 16))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(Tokens.mutedForeground)
                    .contentShape(Circle())
            }
            .accessibilityLabel(app.t("ios.more"))
        }
        .padding(.leading, -10)
        .padding(.top, 2)
    }

    /// Edit, Copy text and Delete on your own Comment; Copy text, Report and Block on someone else's.
    @ViewBuilder private var menuItems: some View {
        if isOwn {
            Button {
                draft = comment.text ?? ""
                isEditing = true
            } label: { Label(app.t("comments.edit"), systemImage: "pencil") }
        }
        Button {
            UIPasteboard.general.string = comment.bodyText
            app.showToast(app.t("ios.copied"))
        } label: { Label(app.t("ios.copyText"), systemImage: "doc.on.doc") }
        if isOwn {
            Divider()
            Button(role: .destructive) { confirmingDelete = true } label: { Label(app.t("common.delete"), systemImage: "trash") }
        } else {
            Button(role: .destructive) {
                app.requireAuth { reporting = true }
            } label: { Label(app.t("ios.report"), systemImage: "flag") }
            if let author = comment.author { BlockButton(username: author, userId: comment.userId) }
        }
    }

    private func saveEdit() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != comment.text else {
            isEditing = false
            return
        }
        do {
            try await model.edit(comment.id, text: text, app.service)
            isEditing = false
        } catch {
            app.showToast(app.t.message(for: error, fallback: "comments.editFailed"), isError: true)
        }
    }
}

/// Like and Reply: 36pt pills with a 44pt hit area. `isOn` is your like (`highlight-tint`) or the
/// Reply you are writing (ink on nothing).
private struct ActionPillStyle: ButtonStyle {
    var isOn: Bool
    var tinted = true

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) { configuration.label }
            .font(.vm(13, .medium))
            .foregroundStyle(isOn ? Tokens.foreground : Tokens.mutedForeground)
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(isOn && tinted ? Tokens.highlightTint : (configuration.isPressed ? Tokens.muted : .clear), in: Capsule())
            .padding(.vertical, 4)
            .contentShape(Capsule())
            .padding(.vertical, -4)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// "Delete this comment?" with what happens to its Replies and the text about to go.
private struct DeleteCommentSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let comment: Comment
    let model: CommentsModel

    var body: some View {
        // Scrolls (and opens to full height) once larger text outgrows 340pt
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.t("comments.deleteConfirm")).displayHeading(20)
                    Text(message).font(.vm(14)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
                }
                Text(comment.bodyText ?? "")
                    .font(.vm(14)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Tokens.surfaceSoft, in: RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border, lineWidth: 1))
                VStack(spacing: 8) {
                    LoadingButton(style: .vm(.destructive, size: .lg, fullWidth: true), action: delete) { Text(app.t("common.delete")) }
                    Button(app.t("common.cancel")) { dismiss() }.buttonStyle(.vm(.ghost, size: .lg, fullWidth: true))
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Tokens.card)
        .presentationDetents([.height(340), .large])
        .presentationDragIndicator(.visible)
    }

    private var message: String {
        switch comment.replyCount {
        case 0: app.t("ios.deleteCommentBody")
        case 1: app.t("ios.deleteCommentReply")
        default: app.t("ios.deleteCommentReplies", ["count": comment.replyCount])
        }
    }

    private func delete() async {
        do {
            try await model.remove(comment, app.service)
            dismiss()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "comments.deleteFailed"), isError: true)
        }
    }
}

/// "Report this poll/comment": a reason, an optional note. The API keeps the first report of a repeat.
struct ReportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let title: String
    let message: String
    let submit: (ReportReason, String) async throws -> Void
    @State private var reason: ReportReason?
    @State private var note = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).displayHeading(20)
                    Text(message).font(.vm(14)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
                }
                VStack(spacing: 0) {
                    ForEach(ReportReason.allCases, id: \.self) { option in
                        Button { reason = option } label: {
                            HStack {
                                Text(app.t("ios.reportReason.\(option.rawValue)")).font(.vm(15))
                                Spacer()
                                if reason == option { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)) }
                            }
                            .foregroundStyle(Tokens.foreground)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(reason == option ? .isSelected : [])
                        .overlay(alignment: .bottom) {
                            if option != ReportReason.allCases.last { Rectangle().fill(Tokens.border).frame(height: 1) }
                        }
                    }
                }
                .card(padding: nil)
                VMTextEditor(placeholder: app.t("ios.reportNote"), text: $note, minHeight: 80, font: .vm(16), autoFocus: false)
                Text("\(note.count) / \(reportNoteMax)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                VStack(spacing: 8) {
                    LoadingButton(style: .vm(.destructive, size: .lg, fullWidth: true), action: send) { Text(app.t("ios.reportSend")) }
                        .disabled(reason == nil || note.count > reportNoteMax)
                    Button(app.t("common.cancel")) { dismiss() }.buttonStyle(.vm(.ghost, size: .lg, fullWidth: true))
                }
            }
            .padding(20)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Tokens.card)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func send() async {
        guard let reason else { return }
        do {
            try await submit(reason, note)
            app.showToast(app.t("ios.reportSent"))
            dismiss()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "ios.reportFailed"), isError: true)
        }
    }
}

/// Writes a top-level Comment: your avatar beside one line that grows, Post once there is something to post.
/// Signed-out visitors sign in first and keep their text.
private struct CommentComposer: View {
    @Environment(AppModel.self) private var app
    let placeholder: String
    let onPost: (String) async -> Bool

    @State private var text = ""
    @State private var isPosting = false
    @FocusState private var isFocused: Bool
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tooLong: Bool { text.count > commentMax }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if let me = app.me {
                    AvatarView(username: me.username, avatarUrl: me.avatarUrl, size: 32).padding(.top, 6)
                }
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(Tokens.mutedForeground), axis: .vertical)
                    .font(.vm(16))
                    .lineLimit(1...8)
                    .focused($isFocused)
                    .padding(.vertical, 10)
                    .fieldChrome(isFocused: isFocused, isInvalid: tooLong, minHeight: 44)
                    .accessibilityLabel(placeholder)
            }
            if isFocused || !text.isEmpty {
                HStack(spacing: 12) {
                    if text.count > commentMax - 200 {
                        Text("\(text.count)/\(commentMax)").font(.vmMono(12))
                            .foregroundStyle(tooLong ? Tokens.destructive : Tokens.mutedForeground)
                    }
                    Button(app.t("comments.post"), action: submit)
                        .buttonStyle(.vm(.default, size: .sm))
                        .disabled(trimmed.isEmpty || tooLong || isPosting)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
    }

    private func submit() {
        guard !trimmed.isEmpty, !tooLong, !isPosting else { return }
        app.requireAuth {
            let value = trimmed
            isPosting = true
            text = ""
            isFocused = false
            Task {
                let ok = await onPost(value)
                isPosting = false
                if !ok { text = value }
            }
        }
    }
}

/// The Reply composer, docked above the keyboard: who it answers, their line, and the text.
/// The screen puts it in its bottom safe area so the thread scrolls underneath.
struct ReplyDock: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let model: CommentsModel

    var body: some View {
        VStack(spacing: 0) {
            if let target = model.replyTarget, !app.isBlocked(target.comment.author) {
                ReplyDockBody(target: target, model: model)
                    .id(target.comment.id)
                    .transition(.vmEnterExit(reduceMotion: reduceMotion))
            }
        }
        .animation(.easeOut(duration: 0.2), value: model.replyTarget)
    }
}

private struct ReplyDockBody: View {
    @Environment(AppModel.self) private var app
    let target: CommentsModel.ReplyTarget
    let model: CommentsModel

    @State private var text = ""
    @State private var isPosting = false
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The "@name " prefix counts toward the limit too.
    private var tooLong: Bool { target.prefix.count + text.count > commentMax }

    var body: some View {
        let author = target.comment.author ?? ""
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrowshape.turn.up.left").font(.system(size: 13, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.t("ios.replyingTo", ["name": author])).font(.vm(12, .medium))
                    Text(target.comment.bodyText ?? "").font(.vm(13)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { model.replyTarget = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 36, height: 36)
                }
                .accessibilityLabel(app.t("ios.cancelReply"))
            }
            .foregroundStyle(Tokens.mutedForeground)
            .padding(.leading, 20).padding(.trailing, 8).padding(.top, 8)

            HStack(alignment: .bottom, spacing: 10) {
                VMTextEditor(placeholder: app.t("comments.replyPlaceholder"), text: $text, minHeight: 44, font: .vm(16),
                             isInvalid: tooLong, autoFocus: true)
                Button(app.t("comments.reply"), action: submit)
                    .buttonStyle(.vm(.default, size: .sm))
                    .accessibilityIdentifier("reply-send")
                    .disabled(trimmed.isEmpty || tooLong || isPosting)
            }
            .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 8)
        }
        .background(Tokens.card)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
    }

    private func submit() {
        guard !trimmed.isEmpty, !tooLong, !isPosting else { return }
        app.requireAuth {
            let value = trimmed
            isPosting = true
            Task {
                do {
                    try await model.reply(value, to: target, author: app.me?.username ?? app.t("comments.you"),
                                          avatarUrl: app.me?.avatarUrl, app.service)
                    // Close only the dock this Reply came from, not one opened while it posted
                    if model.replyTarget?.comment.id == target.comment.id {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        model.replyTarget = nil
                    }
                } catch {
                    app.showToast(app.t.message(for: error, fallback: "comments.postFailed"), isError: true)
                }
                isPosting = false
            }
        }
    }
}

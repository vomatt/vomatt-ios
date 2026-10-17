import Observation
import SwiftUI
import VomattCore

/// Comments on one Poll, newest first, with one level of Replies loaded on demand,
/// optimistic posting and likes (the web's `useComments`).
@Observable
final class CommentsModel {
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
    private var nextCursor: String?
    var hasMore: Bool { nextCursor != nil }

    init(pollId: String, initialTotal: Int?) {
        self.pollId = pollId
        total = initialTotal
    }

    func reload(_ service: VomattService) async {
        status = .loading
        do {
            let page = try await service.comments(pollId: pollId)
            comments = page.items
            replies = [:]
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
        nextCursor = page.nextCursor
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
    func add(_ text: String, author: String, avatarUrl: String?, rootId: String?, _ service: VomattService) async -> Bool {
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
            return true
        } catch {
            if let rootId {
                replies[rootId]?.items.removeAll { $0.id == tempId }
                shiftReplyCount(rootId, by: -1)
            } else {
                comments.removeAll { $0.id == tempId }
            }
            total = shiftCount(total, by: -1)
            return false
        }
    }

    func edit(_ commentId: String, text: String, _ service: VomattService) async -> Bool {
        guard let saved = try? await service.updateComment(pollId: pollId, commentId: commentId, text: text) else { return false }
        replace(commentId) { _ in saved }
        return true
    }

    /// A top-level Comment with Replies becomes a placeholder; anything else leaves the list.
    func remove(_ comment: Comment, _ service: VomattService) async -> Bool {
        do {
            try await service.deleteComment(pollId: pollId, commentId: comment.id)
        } catch {
            return false
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
            return true
        }
        replies[rootId]?.items.removeAll { $0.id == comment.id }
        shiftReplyCount(rootId, by: -1)
        // A placeholder with no Replies left isn't listed by the API either
        comments.removeAll { $0.id == rootId && $0.deleted && $0.replyCount == 0 }
        return true
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
        for key in replies.keys {
            replies[key]?.items = replies[key]?.items.map { $0.id == id ? change($0) : $0 } ?? []
        }
    }
}

/// The discussion under a Poll. Results stay sealed while it is open, so this is where people argue their case.
struct CommentThreadView: View {
    @Environment(AppModel.self) private var app
    @State private var model: CommentsModel

    init(pollId: String, initialTotal: Int?) {
        _model = State(initialValue: CommentsModel(pollId: pollId, initialTotal: initialTotal))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: app.t("comments.title") + (model.total.map { " · \($0)" } ?? ""))
            CommentComposer(placeholder: app.t("comments.placeholder")) { text in
                let ok = await model.add(text, author: app.me?.username ?? app.t("comments.you"),
                                         avatarUrl: app.me?.avatarUrl, rootId: nil, app.service)
                if !ok { app.showToast(app.t("comments.postFailed"), isError: true) }
                return ok
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

            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(model.comments) { comment in
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

private struct CommentItemView: View {
    @Environment(AppModel.self) private var app
    let comment: Comment
    let model: CommentsModel
    /// The Reply composer's starting text; nil while closed.
    @State private var replyPrefix: String?

    var body: some View {
        let replyList = model.replies[comment.id]
        VStack(alignment: .leading, spacing: 12) {
            CommentBodyView(comment: comment, model: model) { openComposer(nil) }
            if comment.replyCount > 0 || replyList != nil || replyPrefix != nil {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(replyList?.items ?? []) { reply in
                        CommentBodyView(comment: reply, model: model) { openComposer(reply.author) }
                    }
                    if replyList?.status == .loading { Skeleton(height: 40, radius: Radius.lg) }
                    if let action = repliesAction(replyList) {
                        Button(action) { Task { await model.loadReplies(comment.id, app.service) } }
                            .font(.vm(12, .medium)).foregroundStyle(Tokens.mutedForeground)
                            .frame(minHeight: 32)
                    }
                    if let replyPrefix {
                        CommentComposer(
                            placeholder: app.t("comments.replyPlaceholder"), initialText: replyPrefix,
                            onCancel: { self.replyPrefix = nil }
                        ) { text in
                            // Show the thread the Reply lands in
                            if replyList == nil, comment.replyCount > 0 { await model.loadReplies(comment.id, app.service) }
                            let ok = await model.add(text, author: app.me?.username ?? app.t("comments.you"),
                                                     avatarUrl: app.me?.avatarUrl, rootId: comment.id, app.service)
                            if ok { self.replyPrefix = nil } else { app.showToast(app.t("comments.postFailed"), isError: true) }
                            return ok
                        }
                        .id(replyPrefix)
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(Tokens.border).frame(width: 1) }
                .padding(.leading, 32)
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
        if list.status == .ready, list.nextCursor != nil { return app.t("comments.moreReplies") }
        return nil
    }

    /// Replying to a Reply addresses its author; the API files it under this Comment.
    private func openComposer(_ author: String?) {
        app.requireAuth { replyPrefix = author.map { "@\($0) " } ?? "" }
    }
}

private struct CommentBodyView: View {
    @Environment(AppModel.self) private var app
    let comment: Comment
    let model: CommentsModel
    let onReply: () -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var confirmingDelete = false

    var body: some View {
        if comment.deleted || comment.author == nil {
            HStack(spacing: 12) {
                Circle().strokeBorder(Tokens.border, style: StrokeStyle(lineWidth: 1, dash: [3, 2])).frame(width: 32, height: 32)
                Text(app.t("comments.deleted")).font(.vm(14)).italic().foregroundStyle(Tokens.mutedForeground)
            }
        } else {
            content(author: comment.author ?? "")
        }
    }

    private func content(author: String) -> some View {
        let isOwn = app.userId != nil && comment.userId == app.userId
        return HStack(alignment: .top, spacing: 12) {
            Button { app.push(.profile(author)) } label: {
                AvatarView(username: author, avatarUrl: comment.authorAvatarUrl, size: 32)
            }
            .buttonStyle(.plain)
            .disabled(comment.isPending)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Button(author) { app.push(.profile(author)) }
                        .font(.vm(12, .medium)).foregroundStyle(Tokens.foreground)
                        .disabled(comment.isPending)
                    Text(app.dates.fromNow(comment.createdAt))
                    if comment.edited { Text(app.t("comments.edited")) }
                }
                .font(.vm(12))
                .foregroundStyle(Tokens.mutedForeground)

                if isEditing {
                    VMTextEditor(placeholder: app.t("comments.edit"), text: $draft, minHeight: 60, font: .vm(14), autoFocus: true)
                    HStack {
                        Spacer()
                        Button(app.t("common.cancel")) { isEditing = false }.buttonStyle(.vm(.ghost, size: .sm))
                        LoadingButton(style: .vm(.default, size: .sm), action: saveEdit) { Text(app.t("common.save")) }
                    }
                } else {
                    Text(comment.text ?? "")
                        .font(.vm(14))
                        .foregroundStyle(Tokens.foreground.opacity(0.85))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !comment.isPending, !isEditing { actions(isOwn: isOwn) }
            }
        }
        .opacity(comment.isPending ? 0.6 : 1)
    }

    private func actions(isOwn: Bool) -> some View {
        HStack(spacing: 16) {
            Button {
                app.requireAuth { Task { await model.toggleLike(comment, app.service) } }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: comment.likedByCurrentUser ? "heart.fill" : "heart")
                        .symbolEffect(.bounce, value: comment.likedByCurrentUser)
                    if comment.likeCount > 0 { Text("\(comment.likeCount)").monospacedDigit() }
                }
                .foregroundStyle(comment.likedByCurrentUser ? Color.pink : Tokens.mutedForeground)
            }
            .accessibilityLabel(app.t("comments.like"))
            .accessibilityValue("\(comment.likeCount)")
            .accessibilityAddTraits(comment.likedByCurrentUser ? .isSelected : [])

            Button(app.t("comments.reply"), action: onReply)
            if isOwn {
                if confirmingDelete {
                    Text(app.t("comments.deleteConfirm"))
                    Button(app.t("common.delete")) { Task { await delete() } }.foregroundStyle(Tokens.destructive).fontWeight(.medium)
                    Button(app.t("common.cancel")) { confirmingDelete = false }
                } else {
                    Button(app.t("comments.edit")) {
                        draft = comment.text ?? ""
                        isEditing = true
                    }
                    Button(app.t("common.delete")) { confirmingDelete = true }
                }
            } else {
                Menu {
                    ReportButton(subject: "Comment \(comment.id) on poll \(model.pollId)", url: app.config.pollURL(model.pollId))
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 28)
                }
                .accessibilityLabel(app.t("ios.more"))
            }
        }
        .font(.vm(12))
        .foregroundStyle(Tokens.mutedForeground)
        .buttonStyle(.plain)
        .frame(minHeight: 32)
    }

    private func saveEdit() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != comment.text else {
            isEditing = false
            return
        }
        if await model.edit(comment.id, text: text, app.service) {
            isEditing = false
        } else {
            app.showToast(app.t("comments.editFailed"), isError: true)
        }
    }

    private func delete() async {
        confirmingDelete = false
        if !(await model.remove(comment, app.service)) { app.showToast(app.t("comments.deleteFailed"), isError: true) }
    }
}

/// Writes a Comment or Reply; signed-out visitors sign in first and keep their text.
private struct CommentComposer: View {
    @Environment(AppModel.self) private var app
    let placeholder: String
    var initialText = ""
    var onCancel: (() -> Void)?
    let onPost: (String) async -> Bool

    @State private var text = ""
    @State private var isPosting = false
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var tooLong: Bool { text.count > commentMax }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            VMTextEditor(placeholder: placeholder, text: $text, minHeight: 60, font: .vm(14), isInvalid: tooLong, autoFocus: onCancel != nil)
            HStack(spacing: 12) {
                if text.count > commentMax - 200 {
                    Text("\(text.count)/\(commentMax)").font(.vmMono(12))
                        .foregroundStyle(tooLong ? Tokens.destructive : Tokens.mutedForeground)
                }
                if let onCancel {
                    Button(app.t("common.cancel"), action: onCancel).buttonStyle(.vm(.ghost, size: .sm))
                }
                Button(onCancel != nil ? app.t("comments.reply") : app.t("comments.post"), action: submit)
                    .buttonStyle(.vm(.default, size: .sm))
                    .disabled(trimmed.isEmpty || tooLong || isPosting)
            }
        }
        .onAppear { if text.isEmpty { text = initialText } }
    }

    private func submit() {
        guard !trimmed.isEmpty, !tooLong, !isPosting else { return }
        app.requireAuth {
            let value = trimmed
            isPosting = true
            text = ""
            // Posted: put the keyboard away so the thread (and the tab bar) are in view
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task {
                let ok = await onPost(value)
                isPosting = false
                if !ok { text = value }
            }
        }
    }
}

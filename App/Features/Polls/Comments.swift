import Observation
import SwiftUI
import VomattCore

/// Comments on one Poll, newest first, with one level of Replies loaded on demand,
/// optimistic posting and likes (the web's `useComments`).
@Observable
final class CommentsModel {
    struct ReplyTarget: Equatable {
        let comment: Comment
        /// What the dock opens with: empty, or a failed Reply's text.
        var text = ""
        var rootId: String { comment.parentId ?? comment.id }
        /// A Reply to a Reply addresses its author; the API files both under the top-level Comment.
        var prefix: String { comment.parentId != nil ? Comment.replyPrefix(to: comment.author ?? "") : "" }
    }

    /// Who a pending Comment is shown as until the saved one replaces it.
    struct PendingAuthor {
        let name: String
        let avatarUrl: String?
        let userId: String?
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
    /// Threads folded back to the Replies they came with ("Hide replies"); showing them again needs no refetch.
    private(set) var folded: Set<String> = []
    /// How many Replies each Comment came with in the list.
    private var previewCounts: [String: Int] = [:]
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
            folded = []
            previewCounts = [:]
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
        for comment in page where replies[comment.id] == nil {
            previewCounts[comment.id] = comment.replies.count
            guard !comment.replies.isEmpty else { continue }
            replies[comment.id] = ReplyList(items: comment.replies, nextCursor: comment.repliesNextCursor)
        }
    }

    /// The Replies on screen under a Comment: all loaded, or only its previews while folded.
    func shownReplies(_ rootId: String) -> [Comment] {
        let items = replies[rootId]?.items ?? []
        return folded.contains(rootId) ? Array(items.prefix(previewCounts[rootId] ?? 0)) : items
    }

    /// Hide replies is offered once Replies past the previews have loaded.
    func canFold(_ rootId: String) -> Bool {
        guard !folded.contains(rootId), let list = replies[rootId], list.status == .ready else { return false }
        return list.items.count > previewCounts[rootId] ?? 0
    }

    func setFolded(_ rootId: String, _ isFolded: Bool) {
        if isFolded { folded.insert(rootId) } else { folded.remove(rootId) }
    }

    /// First call loads the Replies; later calls load the next page.
    func loadReplies(_ rootId: String, _ service: VomattService) async {
        let current = replies[rootId]
        if current?.status == .loading { return }
        // Loaded to the end; a failed page is retried from where it stopped
        if let current, current.status != .error, current.nextCursor == nil { return }
        await fetchReplies(rootId, after: current?.nextCursor, service)
    }

    /// Reads the page of Replies after `cursor`. A Reply the viewer posted meanwhile moves to its place by time,
    /// after the older ones the page brings.
    private func fetchReplies(_ rootId: String, after cursor: String?, _ service: VomattService) async {
        replies[rootId, default: ReplyList()].status = .loading
        do {
            let page = try await service.replies(pollId: pollId, commentId: rootId, cursor: cursor)
            // One read, one write, as in `replace`
            var list = replies[rootId] ?? ReplyList()
            list.items = mergeById(list.items, page.items).sorted { $0.createdAt < $1.createdAt }
            list.nextCursor = page.nextCursor
            list.status = .ready
            replies[rootId] = list
        } catch {
            replies[rootId]?.status = .error
        }
    }

    /// Shows the Comment at once as pending, then swaps in the saved one.
    /// The pending one shows the viewer as they will be once it is saved, so nothing changes then.
    func add(_ text: String, author: PendingAuthor, rootId: String?, _ service: VomattService) async throws {
        let tempId = "pending-\(UUID().uuidString)"
        let pending = Comment(id: tempId, userId: author.userId, author: author.name, authorAvatarUrl: author.avatarUrl,
                              text: text, createdAt: .now, parentId: rootId)
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
            // Replies that loaded meanwhile may already list the saved one
            if let rootId {
                replies[rootId]?.items.removeAll { $0.id == saved.id }
            } else {
                comments.removeAll { $0.id == saved.id }
            }
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

    /// The pending Reply stands in for the dock, which folds now and comes back with the text only if the post
    /// fails and no other dock was opened meanwhile.
    func reply(_ body: String, to target: ReplyTarget, author: PendingAuthor, _ service: VomattService) async throws {
        let rootId = target.rootId
        // Show the thread the Reply lands in
        folded.remove(rootId)
        if replyTarget?.comment.id == target.comment.id { replyTarget = nil }
        // The earlier Replies load alongside; marked loading first so the pending one doesn't read as the whole list
        if replies[rootId] == nil, comments.contains(where: { $0.id == rootId && $0.replyCount > 0 }) {
            replies[rootId] = ReplyList(status: .loading)
            Task { await fetchReplies(rootId, after: nil, service) }
        }
        do {
            try await add(target.prefix + body, author: author, rootId: rootId, service)
        } catch {
            if replyTarget == nil { replyTarget = ReplyTarget(comment: target.comment, text: body) }
            throw error
        }
    }

    func edit(_ commentId: String, text: String, _ service: VomattService) async throws {
        let saved = try await service.updateComment(pollId: pollId, commentId: commentId, text: text)
        replace(commentId) { _ in saved }
    }

    /// A top-level Comment with Replies becomes a placeholder; anything else leaves the list.
    func remove(_ comment: Comment, _ service: VomattService) async throws {
        do {
            try await service.deleteComment(pollId: pollId, commentId: comment.id)
        } catch let error as APIError where error.errorCode == "comment.not_found" {
            // Already deleted, e.g. on another device: it leaves the list all the same
        }
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

    /// A notification's Reply (the web's `#reply-` link): opens the composer under the Comment it names,
    /// loading Replies past the previews until it finds the one named. Nothing opens when the Comment isn't listed.
    func openReply(to link: FeedNotification.CommentInfo, _ service: VomattService) async {
        let rootId = link.parentId ?? link.id
        guard let root = comments.first(where: { $0.id == rootId }) else { return }
        var target = root
        if link.parentId != nil {
            while replies[rootId]?.items.contains(where: { $0.id == link.id }) != true {
                if let list = replies[rootId], list.status != .ready || list.nextCursor == nil { break }
                await loadReplies(rootId, service)
            }
            target = replies[rootId]?.items.first { $0.id == link.id } ?? root
        }
        folded.remove(rootId)
        replyTarget = ReplyTarget(comment: target)
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
        if let target = replyTarget, target.comment.id == id {
            replyTarget = ReplyTarget(comment: change(target.comment), text: target.text)
        }
        // One read, one write: an in-place `replies[key]?.items = …` overlaps its own read
        guard let key = replies.first(where: { $0.value.items.contains { $0.id == id } })?.key, var list = replies[key] else { return }
        list.items = list.items.map { $0.id == id ? change($0) : $0 }
        replies[key] = list
    }
}

private extension AppModel {
    var pendingAuthor: CommentsModel.PendingAuthor {
        .init(name: me?.username ?? t("comments.you"), avatarUrl: me?.avatarUrl, userId: userId)
    }
}

/// The discussion under a Poll. Results stay sealed while it is open, so this is where people argue their case.
/// The screen owns and loads the model so `ReplyDock` can sit above the keyboard.
struct CommentThreadView: View {
    @Environment(AppModel.self) private var app
    let model: CommentsModel
    /// Set on the poll page: the newest Comments only, and See all opens the whole discussion.
    var onSeeAll: (() -> Void)?

    private static let previewCount = 2

    var body: some View {
        let shown = model.comments.filter { !app.isBlocked($0.author) }
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                SectionTitle(text: app.t("comments.title"))
                if let total = model.total {
                    Text("\(total)").font(.vmMono(13)).foregroundStyle(Tokens.mutedForeground)
                }
                Spacer(minLength: 0)
                if let onSeeAll, !shown.isEmpty {
                    Button(app.t("ios.seeAll"), action: onSeeAll)
                        .font(.vm(13, .medium)).foregroundStyle(Tokens.mutedForeground)
                        .frame(minHeight: Metrics.minTarget)
                }
            }
            CommentComposer(placeholder: app.t("comments.placeholder")) { text in
                do {
                    try await model.add(text, author: app.pendingAuthor, rootId: nil, app.service)
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
                ForEach(onSeeAll == nil ? shown : Array(shown.prefix(Self.previewCount))) { comment in
                    CommentItemView(comment: comment, model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.comments.map(\.id))

            if onSeeAll == nil, model.hasMore {
                LoadingButton(style: .vm(.ghost, size: .sm, fullWidth: true), action: { await model.loadMore(app.service) }) {
                    Text(app.t("comments.loadMore")).foregroundStyle(Tokens.mutedForeground)
                }
            }
        }
    }
}

/// The whole discussion on its own screen, reached from See all on the poll page (iOS · Discussion).
struct PollDiscussionView: View {
    let model: CommentsModel
    let title: String

    var body: some View {
        ScrollView {
            CommentThreadView(model: model)
                .pageColumn(720)
                .padding(.vertical, 20)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { ReplyDock(model: model) }
        .canvas()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A top-level Comment with its Replies hung off its avatar rail.
private struct CommentItemView: View {
    @Environment(AppModel.self) private var app
    let comment: Comment
    let model: CommentsModel
    /// View and Hide replace each other, and the row leaves while a page loads; VoiceOver lands back on it.
    @AccessibilityFocusState private var repliesRowFocused: Bool

    private struct RepliesAction {
        let label: String
        let perform: () async -> Void
    }

    var body: some View {
        let replyList = model.replies[comment.id]
        let shown = model.shownReplies(comment.id)
        let replies = shown.filter { !app.isBlocked($0.author) }
        let loading = replyList?.status == .loading
        let action = repliesAction(replyList, shown: shown.count)
        let canFold = model.canFold(comment.id)
        let hasRow = action != nil || canFold
        let hasRail = !replies.isEmpty || loading || hasRow
        VStack(alignment: .leading, spacing: 0) {
            CommentRow(comment: comment, model: model, rail: hasRail ? .root : .none)
            ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                CommentRow(comment: reply, model: model,
                           rail: .reply(continues: index < replies.count - 1 || loading || hasRow))
            }
            if loading {
                RailRow(continues: hasRow) { Skeleton(height: 40, radius: Radius.lg).padding(.vertical, 6) }
            }
            if hasRow {
                RailRow(continues: false) {
                    HStack(spacing: 16) {
                        if let action {
                            repliesButton(action.label, isFirst: true, perform: action.perform)
                        }
                        if canFold {
                            repliesButton(app.t("comments.hideReplies"), isFirst: action == nil) {
                                model.setFolded(comment.id, true)
                            }
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    /// The row's first button takes VoiceOver focus back once the row is redrawn.
    @ViewBuilder private func repliesButton(_ label: String, isFirst: Bool, perform: @escaping () async -> Void) -> some View {
        let button = Button(label) {
            Task {
                await perform()
                repliesRowFocused = true
            }
        }
        .font(.vm(13, .medium)).foregroundStyle(Tokens.mutedForeground)
        .frame(minHeight: 36)
        if isFirst { button.accessibilityFocused($repliesRowFocused) } else { button }
    }

    /// One button walks the Replies: view them, show the folded ones again, retry a failed page, or load more.
    private func repliesAction(_ list: CommentsModel.ReplyList?, shown: Int) -> RepliesAction? {
        let load = { await model.loadReplies(comment.id, app.service) }
        if model.folded.contains(comment.id) {
            return RepliesAction(label: viewLabel(max(1, comment.replyCount - shown), more: shown > 0)) {
                model.setFolded(comment.id, false)
            }
        }
        guard let list else {
            guard comment.replyCount > 0 else { return nil }
            return RepliesAction(label: viewLabel(comment.replyCount, more: false), perform: load)
        }
        if list.status == .error { return RepliesAction(label: app.t("comments.retry"), perform: load) }
        if list.status == .ready, list.nextCursor != nil {
            return RepliesAction(label: viewLabel(max(1, comment.replyCount - list.items.count), more: true), perform: load)
        }
        return nil
    }

    private func viewLabel(_ count: Int, more: Bool) -> String {
        let key = more ? (count == 1 ? "comments.moreReply" : "comments.moreReplies")
            : (count == 1 ? "comments.viewReply" : "comments.viewReplies")
        return app.t(key, ["count": count])
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
    /// A pending Comment dims and says it is posting only once the post takes a moment, so a quick one doesn't flicker.
    @State private var isSlow = false

    private var isReply: Bool { if case .reply = rail { return true } else { return false } }
    private var avatarSize: CGFloat { isReply ? 24 : 32 }
    private var isOwn: Bool { app.userId != nil && comment.userId == app.userId }
    private var isTarget: Bool { model.replyTarget?.comment.id == comment.id }

    /// The body with the handles the server resolved as links to their profiles (underlined, not colored).
    private var linkedBody: AttributedString {
        comment.bodySegments.reduce(into: AttributedString()) { result, segment in
            var part = AttributedString(segment.text)
            if let name = segment.username {
                var components = URLComponents()
                components.scheme = "vomatt-mention"
                components.host = "profile"
                components.queryItems = [URLQueryItem(name: "name", value: name)]
                guard let url = components.url else { result.append(part); return }
                part.link = url
                part.underlineStyle = .single
            }
            result.append(part)
        }
    }

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
                } else if comment.isPending {
                    Text(app.t("comments.posting")).opacity(isSlow ? 1 : 0)
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
                Text(linkedBody)
                    .font(.vm(15))
                    .foregroundStyle(Tokens.foreground)
                    .tint(Tokens.foreground)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.openURL, OpenURLAction { url in
                        guard url.scheme == "vomatt-mention",
                              let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                                  .queryItems?.first(where: { $0.name == "name" })?.value
                        else { return .systemAction }
                        app.push(.profile(name))
                        return .handled
                    })
            }

            // Held in place while pending, so the Comment doesn't grow once it is saved
            if !isEditing {
                actions
                    .opacity(comment.isPending ? 0 : 1)
                    .disabled(comment.isPending)
                    .accessibilityHidden(comment.isPending)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(isTarget ? Tokens.highlightTint : .clear, in: RoundedRectangle(cornerRadius: Radius.xl))
        .padding(.horizontal, -8).padding(.vertical, -4)
        .contentShape(RoundedRectangle(cornerRadius: Radius.xl))
        .contextMenu { if !comment.isPending, !isEditing { menuItems } }
        .opacity(comment.isPending && isSlow ? 0.6 : 1)
        .animation(.easeOut(duration: 0.2), value: isSlow)
        .animation(.easeOut(duration: 0.2), value: comment.isPending)
        .task(id: comment.isPending) {
            guard comment.isPending else { return }
            try? await Task.sleep(for: .milliseconds(400))
            isSlow = true
        }
        .animation(.easeOut(duration: 0.15), value: isTarget)
        .sheet(isPresented: $confirmingDelete) { DeleteCommentSheet(comment: comment, model: model) }
        .sheet(isPresented: $reporting) { ReportSheet(pollId: model.pollId, commentId: comment.id) }
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
        Button {
            UIPasteboard.general.url = commentURL
            app.showToast(app.t("comments.linkCopied"))
        } label: { Label(app.t("comments.copyLink"), systemImage: "link") }
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

    /// The poll page's link to this Comment (the web's `commentHash`), which scrolls to it there.
    private var commentURL: URL? {
        var components = URLComponents(url: app.config.pollURL(model.pollId), resolvingAgainstBaseURL: false)
        components?.fragment = "comment-" + (comment.parentId.map { "\($0)/\(comment.id)" } ?? comment.id)
        return components?.url
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

/// Reports someone else's comment, or with no `commentId` the poll itself, to the moderators: a reason
/// and an optional note (the web's `ReportCommentDialog`). The API keeps the first report of a repeat.
struct ReportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pollId: String
    var commentId: String?
    @State private var reason: ReportReason?
    @State private var note = ""

    /// Comment and poll reports share their reasons, with their own words around them.
    private var copy: String { commentId == nil ? "poll" : "comments" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(app.t("\(copy).reportTitle")).displayHeading(20)
                    Text(app.t("\(copy).reportBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground).lineSpacing(3)
                }
                VStack(spacing: 0) {
                    ForEach(ReportReason.allCases, id: \.self) { option in
                        Button { reason = option } label: {
                            HStack {
                                Text(app.t("comments.reportReason.\(option.rawValue)")).font(.vm(15))
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
                            if option != ReportReason.allCases.last { Hairline() }
                        }
                    }
                }
                .card(padding: nil)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(app.t("comments.reportReasonLabel"))
                VMTextEditor(placeholder: app.t("comments.reportNote"), text: $note, minHeight: 80, font: .vm(16), autoFocus: false)
                Text("\(note.count) / \(reportNoteMax)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                VStack(spacing: 8) {
                    LoadingButton(style: .vm(.destructive, size: .lg, fullWidth: true), action: send) { Text(app.t("\(copy).report")) }
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
            if let commentId {
                try await app.service.reportComment(pollId: pollId, commentId: commentId, reason: reason, note: note)
            } else {
                try await app.service.reportPoll(id: pollId, reason: reason, note: note)
            }
            app.showToast(app.t("\(copy).reportDone"))
            dismiss()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "\(copy).reportFailed"), isError: true)
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
                    .mentionSuggestions(text: $text, opens: .bottom)
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

    @State private var text: String
    @State private var isPosting = false
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    init(target: CommentsModel.ReplyTarget, model: CommentsModel) {
        self.target = target
        self.model = model
        _text = State(initialValue: target.text)
    }

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
                    .mentionSuggestions(text: $text, opens: .top)
                Button(app.t("comments.reply"), action: submit)
                    .buttonStyle(.vm(.default, size: .sm))
                    .accessibilityIdentifier("reply-send")
                    .disabled(trimmed.isEmpty || tooLong || isPosting)
            }
            .padding(.leading, 20).padding(.trailing, 12).padding(.vertical, 8)
        }
        .background(Tokens.card)
        .overlay(alignment: .top) { Hairline() }
    }

    private func submit() {
        guard !trimmed.isEmpty, !tooLong, !isPosting else { return }
        app.requireAuth {
            let value = trimmed
            isPosting = true
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task {
                do {
                    try await model.reply(value, to: target, author: app.pendingAuthor, app.service)
                } catch {
                    app.showToast(app.t.message(for: error, fallback: "comments.postFailed"), isError: true)
                }
                isPosting = false
            }
        }
    }
}

/// Suggests people while an `@handle` is typed (the web's `MentionTextarea`): the people the viewer follows on
/// a bare `@`, a username search once letters follow. A tap, or Return or Tab on a hardware keyboard, puts in
/// `@username `; the arrows move and Escape closes it. Guests get no list.
private struct MentionSuggestions: ViewModifier {
    @Environment(AppModel.self) private var app
    @Binding var text: String
    /// Under the field, or over it where the field is docked at the bottom.
    let opens: VerticalEdge

    private struct Results {
        let term: String
        let users: [UserSummary]
    }

    @State private var results: Results?
    @State private var highlighted = 0
    /// Escape closes the list for the handle starting here until another one is started.
    @State private var dismissedAt: Int?

    // A SwiftUI TextField doesn't report its caret on iOS 17, so the handle is the one the text ends in
    private var mention: ActiveMention? {
        guard app.me != nil, let mention = Mention.active(in: text, caret: text.count), mention.start != dismissedAt else { return nil }
        return mention
    }

    private var users: [UserSummary] {
        guard let mention, let results, results.term == mention.term else { return [] }
        return results.users
    }

    func body(content: Content) -> some View {
        let users = users
        let active = min(highlighted, max(0, users.count - 1))
        VStack(spacing: 4) {
            if opens == .top, !users.isEmpty { list(users, active: active) }
            content.onKeyPress(phases: .down) { press in handle(press, users: users, active: active) }
            if opens == .bottom, !users.isEmpty { list(users, active: active) }
        }
        .task(id: mention?.term) { await lookUp(mention?.term) }
        .onChange(of: users.isEmpty) { _, isEmpty in
            if !isEmpty { AccessibilityNotification.Announcement(app.t("comments.mentionSuggestions")).post() }
        }
    }

    private func list(_ users: [UserSummary], active: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                Button { choose(user) } label: {
                    HStack(spacing: 12) {
                        AvatarView(username: user.username, avatarUrl: user.avatarUrl, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(user.username).font(.vm(14, .medium)).foregroundStyle(Tokens.popoverForeground)
                            if let name = user.displayName {
                                Text(name).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
                            }
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(minHeight: Metrics.minTarget)
                    .background(index == active ? Tokens.muted : .clear, in: RoundedRectangle(cornerRadius: Radius.lg))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == active ? .isSelected : [])
            }
        }
        .padding(6)
        .background(Tokens.popover, in: RoundedRectangle(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.t("comments.mentionSuggestions"))
        .transition(.opacity)
    }

    private func handle(_ press: KeyPress, users: [UserSummary], active: Int) -> KeyPress.Result {
        guard !users.isEmpty else { return .ignored }
        switch press.key {
        case .downArrow, .upArrow:
            highlighted = (active + (press.key == .downArrow ? 1 : -1) + users.count) % users.count
        case .return where press.modifiers.isDisjoint(with: [.command, .control]), .tab:
            choose(users[active])
        case .escape:
            dismissedAt = mention?.start
        default:
            return .ignored
        }
        return .handled
    }

    private func choose(_ user: UserSummary) {
        guard let mention else { return }
        text = Mention.insert(user.username, into: text, replacing: mention).text
    }

    private func lookUp(_ term: String?) async {
        guard let term, let viewer = app.me?.username else { return }
        if !term.isEmpty {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        var found: [UserSummary] = []
        do {
            found = term.isEmpty
                ? try await app.service.following(username: viewer).items
                : try await app.service.searchUsers(term, limit: Mention.maxSuggestions + 1).items
        } catch {
            // A failed lookup just shows no suggestions; the text is still a valid mention
        }
        guard !Task.isCancelled else { return }
        results = Results(term: term, users: Mention.suggestions(found, viewer: viewer))
        highlighted = 0
    }
}

private extension View {
    func mentionSuggestions(text: Binding<String>, opens: VerticalEdge) -> some View {
        modifier(MentionSuggestions(text: text, opens: opens))
    }
}

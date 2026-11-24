import Foundation

public enum LoadStatus: Sendable { case loading, ready, error }

/// The loaded Replies of one top-level Comment, oldest first.
public struct ReplyList: Equatable, Sendable {
    public var items: [Comment]
    public var nextCursor: String?
    public var status: LoadStatus

    public init(items: [Comment] = [], nextCursor: String? = nil, status: LoadStatus = .ready) {
        self.items = items
        self.nextCursor = nextCursor
        self.status = status
    }
}

/// The Comments listed on one Poll, newest first, with the Replies loaded under each (the web's `useComments` lists).
public struct CommentThread: Equatable, Sendable {
    public var comments: [Comment]
    public var replies: [String: ReplyList]
    public var nextCursor: String?
    /// Whether pages after the first are listed; a refresh then keeps them and the cursor after them.
    public var hasLaterPages: Bool

    public init(comments: [Comment] = [], replies: [String: ReplyList] = [:], nextCursor: String? = nil,
                hasLaterPages: Bool = false) {
        self.comments = comments
        self.replies = replies
        self.nextCursor = nextCursor
        self.hasLaterPages = hasLaterPages
    }

    /// Comments and Replies still posting; the Poll's count doesn't include them yet.
    public var postingCount: Int {
        (comments + replies.values.flatMap(\.items)).filter { $0.id.hasPrefix(pendingCommentPrefix) }.count
    }

    /// Puts a new first page in place. With `keepLoaded` (a refresh), the Comments loaded after it stay,
    /// so a Reply open under one isn't lost, and so do Replies loaded past the previews. A page that reaches
    /// none of the Comments listed starts over, or those between would never load. Either way a Comment or
    /// Reply in `postedHere` (or still posting) that the page doesn't list stays. Returns whether it kept the list.
    @discardableResult
    public mutating func applyFirstPage(_ page: CursorPage<Comment>, keepLoaded: Bool,
                                        postedHere: Set<String>) -> Bool {
        let listed = Set(page.items.map(\.id))
        // Posted while the page loaded, so not on it; one the page has comes from the page
        let isPostedOnly = { (c: Comment) in
            !listed.contains(c.id) && (c.id.hasPrefix(pendingCommentPrefix) || postedHere.contains(c.id))
        }
        let keep = keepLoaded && comments.contains { listed.contains($0.id) }
        // Older than the new first page, so pushed past it; one the page skips is gone (deleted elsewhere)
        let isOlder = { (c: Comment) in
            guard keep, let last = page.items.last else { return false }
            return !listed.contains(c.id) && !isPostedOnly(c) && c.createdAt <= last.createdAt
        }
        let previous = self
        comments = previous.comments.filter(isPostedOnly) + page.items + previous.comments.filter(isOlder)

        var preview = Self.previewLists(page.items)
        if keep {
            // Replies loaded past the preview, and one still posting, stay
            var merged = previous.replies
            for (rootId, list) in preview {
                if var loaded = merged[rootId] {
                    loaded.items = mergeById(loaded.items, list.items).sorted { $0.createdAt < $1.createdAt }
                    merged[rootId] = loaded
                } else {
                    merged[rootId] = list
                }
            }
            replies = merged
        } else {
            // Starting over still keeps a Reply that is posting, so it is shown once saved
            for (rootId, list) in previous.replies {
                let posting = list.items.filter(isPostedOnly)
                guard !posting.isEmpty else { continue }
                var base = preview[rootId] ?? ReplyList()
                base.items = mergeById(base.items, posting).sorted { $0.createdAt < $1.createdAt }
                preview[rootId] = base
            }
            replies = preview
            hasLaterPages = false
        }
        if !hasLaterPages { nextCursor = page.nextCursor }
        return keep
    }

    /// The Replies a page of Comments previews, as Reply lists that continue from their cursor.
    private static func previewLists(_ page: [Comment]) -> [String: ReplyList] {
        var lists: [String: ReplyList] = [:]
        for comment in page where !comment.replies.isEmpty {
            lists[comment.id] = ReplyList(items: comment.replies, nextCursor: comment.repliesNextCursor)
        }
        return lists
    }
}

/// The id prefix of a Comment shown before the API saved it.
public let pendingCommentPrefix = "pending-"

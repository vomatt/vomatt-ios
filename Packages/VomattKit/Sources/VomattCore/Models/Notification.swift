import Foundation

/// One item of GET /notifications. Which of `actor`, `poll` and `comment` are set depends on `kind`.
public struct FeedNotification: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// A Poll you own, hold a Ballot in or are invited to has Ended.
        case result
        /// An Invite-only Poll you were invited to was Cancelled before it opened.
        case cancelled
        case invitation
        case followed
        case comment
        /// Someone wrote the viewer's @username in a Comment; the row reads like a Comment's.
        case mention
        case closingSoon
    }

    public struct PollInfo: Hashable, Sendable {
        public var id: String
        public var title: String
        public var startTime: Date?
        public var endTime: Date?
        public var isEnded: Bool
        /// Participants, visible at all times; never per-option counts.
        public var turnout: Int
        /// The viewer's Ballot; nil without one, or once an Anonymous Ballot of an Ended Poll is sealed.
        public var myOptionId: String?
        /// Ended only: the option(s) with the most Ballots, in display order. nil until the Poll has Ended.
        public var winningOptionIds: [String]?
        public var winningOptionLabels: [String]?
        public var tie: Bool?

        public init(
            id: String, title: String, startTime: Date? = nil, endTime: Date? = nil, isEnded: Bool = false, turnout: Int = 0,
            myOptionId: String? = nil, winningOptionIds: [String]? = nil, winningOptionLabels: [String]? = nil, tie: Bool? = nil
        ) {
            self.id = id
            self.title = title
            self.startTime = startTime
            self.endTime = endTime
            self.isEnded = isEnded
            self.turnout = turnout
            self.myOptionId = myOptionId
            self.winningOptionIds = winningOptionIds
            self.winningOptionLabels = winningOptionLabels
            self.tie = tie
        }

        /// Whether the viewer's Ballot is among the winners. nil while the outcome or the Ballot is unknown.
        public var viewerWon: Bool? {
            guard let myOptionId, let winningOptionIds else { return nil }
            return winningOptionIds.contains(myOptionId)
        }
    }

    public struct CommentInfo: Hashable, Sendable {
        public var id: String
        /// The Comment a Reply is under; nil for a top-level Comment.
        public var parentId: String?
        public var excerpt: String

        public init(id: String, parentId: String? = nil, excerpt: String = "") {
            self.id = id
            self.parentId = parentId
            self.excerpt = excerpt
        }
    }

    public let id: String
    public var kind: Kind
    public var createdAt: Date
    public var read: Bool
    public var actor: UserSummary?
    public var poll: PollInfo?
    public var comment: CommentInfo?

    public init(
        id: String, kind: Kind, createdAt: Date, read: Bool = false,
        actor: UserSummary? = nil, poll: PollInfo? = nil, comment: CommentInfo? = nil
    ) {
        self.id = id
        self.kind = kind
        self.createdAt = createdAt
        self.read = read
        self.actor = actor
        self.poll = poll
        self.comment = comment
    }
}

/// Which notification kinds appear in the feed and the unread count. Following has no switch.
public struct NotificationPreferences: Hashable, Sendable {
    /// RESULT and CANCELLED
    public var resultsIn: Bool
    public var invitations: Bool
    public var comments: Bool
    public var mentions: Bool
    public var closingSoon: Bool

    public init(resultsIn: Bool = true, invitations: Bool = true, comments: Bool = true, mentions: Bool = true, closingSoon: Bool = false) {
        self.resultsIn = resultsIn
        self.invitations = invitations
        self.comments = comments
        self.mentions = mentions
        self.closingSoon = closingSoon
    }
}

/// Why a Poll or a Comment is reported (`POST …/report`).
public enum ReportReason: String, CaseIterable, Sendable {
    case spam, harassment, hate, misinformation, other
}

/// The most characters of a report's note.
public let reportNoteMax = 500

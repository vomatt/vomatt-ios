import Foundation

public let pollTitleMax = 200
public let pollDescriptionMax = 1000
public let pollOptionMax = 100
public let pollOptionsMin = 2
public let pollOptionsLimit = 10
public let commentMax = 2000

/// Who can reach the Poll: anyone (listed in Feed, Explore and Search), only
/// people with its link, or only the owner and its Invitees. Fixed once Open.
public enum Audience: String, Codable, CaseIterable, Sendable {
    case `public`
    case unlisted
    case inviteOnly = "invite-only"
}

/// Who can see what each person chose, once the Poll has Ended.
public enum VoterVisibility: String, Codable, CaseIterable, Sendable {
    case nobody
    case owner
    case signedIn = "signed-in"
}

/// The level shown to the viewer: on an Invite-only Poll "signed in" covers only the owner and Invitees.
public enum VisibilityLevel: String, Sendable {
    case nobody, owner
    case signedIn = "signed-in"
    case invited
}

public struct PollOption: Identifiable, Hashable, Sendable {
    public let id: String
    public var text: String
    public var displayOrder: Int
    /// Withheld (nil) while the Poll is Sealed.
    public var votes: Int?

    public init(id: String, text: String, displayOrder: Int = 0, votes: Int? = nil) {
        self.id = id
        self.text = text
        self.displayOrder = displayOrder
        self.votes = votes
    }
}

public struct Tag: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var slug: String
    public var usageCount: Int?

    public init(id: String, name: String, slug: String, usageCount: Int? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.usageCount = usageCount
    }
}

/// The API's `VoteResponse`. Option counts are nil (Sealed) until the Poll Ends.
public struct Poll: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var description: String?
    public var active: Bool
    public var votingActive: Bool
    public var voterVisibility: VoterVisibility?
    public var audience: Audience?
    public var creatorId: String
    public var creatorUsername: String
    public var creatorAvatarUrl: String?
    public var createdAt: Date
    public var startTime: Date
    /// When it ends, or actually ended.
    public var endTime: Date?
    /// The end time the owner set; `endTime` earlier than this means it ended early.
    public var deadline: Date?
    /// Invite-only Polls only.
    public var inviteeCount: Int?
    /// Owner only: whether the Poll can still be Deleted.
    public var deletable: Bool?
    public var participantCount: Int?
    public var commentCount: Int?
    /// Distinct signed-in users who shared the Poll.
    public var shareCount: Int?
    /// The viewer's Ballot; nil without one (or signed out).
    public var myOptionId: String?
    /// Whether the viewer's Ballot is left out of the voter list; nil without a Ballot.
    public var myBallotAnonymous: Bool?
    /// Only set on My Polls: an unread Invitation or Ended Notification.
    public var unread: Bool?
    /// Whether the viewer saved the Poll; nil when signed out.
    public var bookmarked: Bool?
    public var options: [PollOption]
    public var tags: [Tag]

    public init(
        id: String, title: String, description: String? = nil, active: Bool = true,
        votingActive: Bool = true, voterVisibility: VoterVisibility? = nil, audience: Audience? = nil,
        creatorId: String, creatorUsername: String, creatorAvatarUrl: String? = nil,
        createdAt: Date, startTime: Date, endTime: Date?, deadline: Date? = nil,
        inviteeCount: Int? = nil, deletable: Bool? = nil,
        participantCount: Int? = nil, commentCount: Int? = nil, shareCount: Int? = nil, myOptionId: String? = nil,
        myBallotAnonymous: Bool? = nil, unread: Bool? = nil, bookmarked: Bool? = nil, options: [PollOption], tags: [Tag] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.active = active
        self.votingActive = votingActive
        self.voterVisibility = voterVisibility
        self.audience = audience
        self.creatorId = creatorId
        self.creatorUsername = creatorUsername
        self.creatorAvatarUrl = creatorAvatarUrl
        self.createdAt = createdAt
        self.startTime = startTime
        self.endTime = endTime
        self.deadline = deadline
        self.inviteeCount = inviteeCount
        self.deletable = deletable
        self.participantCount = participantCount
        self.commentCount = commentCount
        self.shareCount = shareCount
        self.myOptionId = myOptionId
        self.myBallotAnonymous = myBallotAnonymous
        self.unread = unread
        self.bookmarked = bookmarked
        self.options = options
        self.tags = tags
    }
}

/// GET /votes/{id}/results, only once the Poll has Ended.
public struct PollResults: Hashable, Sendable {
    public struct Option: Identifiable, Hashable, Sendable {
        public let id: String
        public var text: String
        public var voteCount: Int
    }

    public let id: String
    public var totalParticipants: Int?
    public var options: [Option]
}

/// One Participant's Ballot, from GET /votes/{id}/voters (Ended Polls only).
public struct Voter: Identifiable, Hashable, Sendable {
    public var id: String { userId }
    public let userId: String
    public var username: String
    public var avatarUrl: String?
    /// nil for everyone while the Poll holds an Anonymous Ballot other than the viewer's own.
    public var optionId: String?
    public var votedAt: Date?
}

/// A user added by ID or an email address (never says whether it belongs to an account).
public struct Person: Hashable, Sendable {
    public var userId: String?
    public var username: String?
    public var avatarUrl: String?
    public var email: String?

    public init(userId: String? = nil, username: String? = nil, avatarUrl: String? = nil, email: String? = nil) {
        self.userId = userId
        self.username = username
        self.avatarUrl = avatarUrl
        self.email = email
    }

    /// Unique within one list: an email is listed only by that address, even once tied to a user.
    public var key: String { email ?? userId ?? "" }
}

/// An Invitee of an Invite-only Poll, as its owner sees it. One who holds a Ballot can't be removed.
public struct Invitee: Identifiable, Hashable, Sendable {
    public var id: String { person.key }
    public var person: Person
    public var hasBallot: Bool
    public var invitedAt: Date?
}

/// Who to invite to an Invite-only Poll; Groups are copied in as their current members.
public struct InviteesInput: Hashable, Sendable {
    public var userIds: [String]
    public var emails: [String]
    public var groupIds: [String]

    public init(userIds: [String] = [], emails: [String] = [], groupIds: [String] = []) {
        self.userIds = userIds
        self.emails = emails
        self.groupIds = groupIds
    }
}

/// What the creator hands to the service.
public struct PollInput: Hashable, Sendable {
    public var title: String
    public var description: String?
    public var options: [String]
    public var startTime: Date
    public var endTime: Date
    public var voterVisibility: VoterVisibility
    /// nil: Public on create, unchanged on edit.
    public var audience: Audience?
    /// Invite-only only. On edit these replace the current Invitees.
    public var invitees: InviteesInput?

    public init(
        title: String, description: String?, options: [String], startTime: Date, endTime: Date,
        voterVisibility: VoterVisibility, audience: Audience?, invitees: InviteesInput?
    ) {
        self.title = title
        self.description = description
        self.options = options
        self.startTime = startTime
        self.endTime = endTime
        self.voterVisibility = voterVisibility
        self.audience = audience
        self.invitees = invitees
    }
}

/// `author` is the commenter's username. A deleted Comment that still has
/// Replies stays as a placeholder: `deleted`, with no author or text.
public struct Comment: Identifiable, Hashable, Sendable {
    public let id: String
    public var userId: String?
    public var author: String?
    public var authorAvatarUrl: String?
    public var text: String?
    public var createdAt: Date
    public var likeCount: Int
    public var edited: Bool
    public var likedByCurrentUser: Bool
    public var parentId: String?
    public var replyCount: Int
    public var deleted: Bool
    /// The first Replies of a top-level Comment as the list returns them (oldest first, at most 2).
    public var replies: [Comment]
    /// Passed as `cursor` to load the rest of the Replies; nil when `replies` holds them all.
    public var repliesNextCursor: String?
    /// The users the server resolved from `@handles` in `text`, in order of first appearance. Only these link.
    public var mentions: [Mention]

    public struct Mention: Hashable, Sendable {
        public let userId: String
        public let username: String
        public init(userId: String, username: String) { self.userId = userId; self.username = username }
    }

    public init(
        id: String, userId: String? = nil, author: String?, authorAvatarUrl: String? = nil,
        text: String?, createdAt: Date, likeCount: Int = 0, edited: Bool = false,
        likedByCurrentUser: Bool = false, parentId: String? = nil, replyCount: Int = 0, deleted: Bool = false,
        replies: [Comment] = [], repliesNextCursor: String? = nil, mentions: [Mention] = []
    ) {
        self.mentions = mentions
        self.replies = replies
        self.repliesNextCursor = repliesNextCursor
        self.id = id
        self.userId = userId
        self.author = author
        self.authorAvatarUrl = authorAvatarUrl
        self.text = text
        self.createdAt = createdAt
        self.likeCount = likeCount
        self.edited = edited
        self.likedByCurrentUser = likedByCurrentUser
        self.parentId = parentId
        self.replyCount = replyCount
        self.deleted = deleted
    }

    public var isPending: Bool { id.hasPrefix("pending-") }
}

public extension Comment {
    /// A run of the body: plain text, or an `@handle` to link to `username`'s profile.
    struct Segment: Hashable, Sendable {
        public let text: String
        public let username: String?
    }

    /// `bodyText` cut at the handles `mentions` names (case-insensitive). Every other `@handle`, one
    /// preceded by a letter, digit or `_` (`a@b.com`), or one the server left out stays plain text.
    var bodySegments: [Segment] {
        let body = bodyText ?? ""
        guard !mentions.isEmpty else { return [Segment(text: body, username: nil)] }
        let known = Dictionary(mentions.map { ($0.username.lowercased(), $0.username) }, uniquingKeysWith: { first, _ in first })
        func isHandleChar(_ c: Character) -> Bool { c == "_" || (c.isASCII && (c.isLetter || c.isNumber)) }
        var segments: [Segment] = []
        var plain = ""
        var i = body.startIndex
        var previous: Character?
        while i < body.endIndex {
            let c = body[i]
            if c == "@", !(previous.map { $0 == "_" || $0.isLetter || $0.isNumber } ?? false) {
                let start = body.index(after: i)
                var end = start
                while end < body.endIndex, isHandleChar(body[end]) { end = body.index(after: end) }
                if let name = known[body[start..<end].lowercased()] {
                    if !plain.isEmpty { segments.append(Segment(text: plain, username: nil)); plain = "" }
                    segments.append(Segment(text: String(body[i..<end]), username: name))
                    previous = body[body.index(before: end)]
                    i = end
                    continue
                }
            }
            plain.append(c)
            previous = c
            i = body.index(after: i)
        }
        if !plain.isEmpty { segments.append(Segment(text: plain, username: nil)) }
        return segments
    }

    /// Replying to a Reply opens the text with "@name " (the web's reply prefix). Split off, the name
    /// becomes the addressee and the body reads without it. Top-level Comments keep their text as written.
    var addressee: String? { mentionSplit?.name }
    var bodyText: String? { mentionSplit?.body ?? text }

    /// What a Reply to `author`'s Reply starts with.
    static func replyPrefix(to author: String) -> String { "@\(author) " }

    private var mentionSplit: (name: String, body: String)? {
        guard parentId != nil, let text, text.hasPrefix("@") else { return nil }
        let afterAt = text.dropFirst()
        guard let space = afterAt.firstIndex(where: \.isWhitespace), space > afterAt.startIndex else { return nil }
        let body = afterAt[space...].drop(while: \.isWhitespace)
        guard !body.isEmpty else { return nil }
        return (String(afterAt[..<space]), String(body))
    }
}

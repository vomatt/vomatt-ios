import Foundation

/// GET /users/{username}. Fields the owner hides come back nil.
public struct UserProfile: Hashable, Sendable {
    public var id: String?
    public var username: String
    public var displayName: String?
    public var firstName: String?
    public var lastName: String?
    public var bio: String?
    public var avatarUrl: String?
    public var joinedAt: Date?
    public var totalPolls: Int
    public var totalVotes: Int
    /// Whether the viewer follows / has blocked this user; nil when signed out.
    public var isFollowing: Bool?
    public var isBlocked: Bool?
    public var followersCount: Int
    public var followingCount: Int
    /// Whether this user follows the viewer; nil when signed out.
    public var followsYou: Bool?
    /// Followers of this user whom the viewer follows; nil when signed out and on the viewer's own profile.
    public var mutualFollowersCount: Int?
    /// The first 3 of them.
    public var mutualFollowersPreview: [UserSummary]
    /// A community account (a group's page run by several members), shown with a badge.
    public var isCommunity: Bool
    /// nil unless the owner made it visible (hidden by default), or never set.
    public var gender: Gender?

    public init(
        id: String? = nil, username: String, displayName: String? = nil, firstName: String? = nil, lastName: String? = nil,
        bio: String? = nil, avatarUrl: String? = nil, joinedAt: Date? = nil, totalPolls: Int = 0, totalVotes: Int = 0,
        isFollowing: Bool? = nil, isBlocked: Bool? = nil,
        followersCount: Int = 0, followingCount: Int = 0, followsYou: Bool? = nil,
        mutualFollowersCount: Int? = nil, mutualFollowersPreview: [UserSummary] = [], isCommunity: Bool = false,
        gender: Gender? = nil
    ) {
        self.id = id
        self.gender = gender
        self.isCommunity = isCommunity
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.followsYou = followsYou
        self.mutualFollowersCount = mutualFollowersCount
        self.mutualFollowersPreview = mutualFollowersPreview
        self.isFollowing = isFollowing
        self.isBlocked = isBlocked
        self.username = username
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.joinedAt = joinedAt
        self.totalPolls = totalPolls
        self.totalVotes = totalVotes
    }
}

/// GET /users/me: the signed-in user's own profile.
public struct MyProfile: Hashable, Sendable {
    public let id: String
    public var username: String
    public var email: String?
    public var displayName: String?
    public var bio: String?
    public var avatarUrl: String?
    public var firstName: String?
    public var lastName: String?
    /// `yyyy-MM-dd`; once set it can be changed but not cleared.
    public var birthday: String?
    public var joinedAt: Date?
    public var totalPolls: Int
    public var totalVotes: Int
    /// Polls the caller created / holds a Ballot in, as My Polls lists them; nil from an older API.
    public var createdPollCount: Int?
    public var votedPollCount: Int?
    public var followersCount: Int
    public var followingCount: Int
    public var visibilitySettings: [String: Bool]
    /// Whether a first Ballot is Anonymous unless the voter says otherwise.
    public var anonymousBallotByDefault: Bool
    /// nil when never provided; once set it can be changed but not cleared.
    public var gender: Gender?
    /// E.164; nil when the account signed up with email only.
    public var phoneNumber: String?
    /// The phone number was verified by SMS (phone sign-up or `verifyPhoneBind`).
    public var phoneVerified: Bool
    /// nil from an API older than paid plans.
    public var plan: Plan?
    public var communityQuota: CommunityQuota?

    public init(
        id: String, username: String, email: String? = nil, displayName: String? = nil, bio: String? = nil,
        avatarUrl: String? = nil, firstName: String? = nil, lastName: String? = nil, birthday: String? = nil,
        joinedAt: Date? = nil, totalPolls: Int = 0, totalVotes: Int = 0, createdPollCount: Int? = nil, votedPollCount: Int? = nil, followersCount: Int = 0, followingCount: Int = 0,
        visibilitySettings: [String: Bool] = [:], anonymousBallotByDefault: Bool = false,
        gender: Gender? = nil, phoneNumber: String? = nil, phoneVerified: Bool = false,
        plan: Plan? = nil, communityQuota: CommunityQuota? = nil
    ) {
        self.gender = gender
        self.phoneNumber = phoneNumber
        self.phoneVerified = phoneVerified
        self.plan = plan
        self.communityQuota = communityQuota
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.firstName = firstName
        self.lastName = lastName
        self.birthday = birthday
        self.joinedAt = joinedAt
        self.totalPolls = totalPolls
        self.totalVotes = totalVotes
        self.createdPollCount = createdPollCount
        self.votedPollCount = votedPollCount
        self.visibilitySettings = visibilitySettings
        self.anonymousBallotByDefault = anonymousBallotByDefault
    }
}

/// The API's gender values, in the order Edit profile offers them.
public enum Gender: String, CaseIterable, Sendable {
    case male = "MALE"
    case female = "FEMALE"
    case other = "OTHER"
    case undisclosed = "UNDISCLOSED"

    /// The gender as the viewer's language words it (the web's `genderLabel`).
    public var translationKey: String { "profile.genders.\(rawValue)" }
}

public enum Plan: String, Sendable {
    case free = "FREE"
    case pro = "PRO"
}

/// The community accounts the user owns against their plan's limit.
public struct CommunityQuota: Hashable, Sendable {
    /// Unlocked ones the user is an OWNER of.
    public var owned: Int
    public var limit: Int
    /// The user owns more than `limit` unlocked and must choose which to keep.
    public var selectionRequired: Bool
    /// When the earliest created are kept and the rest locked if the user hasn't chosen; nil unless `selectionRequired`.
    public var selectionDeadline: Date?

    public init(owned: Int, limit: Int, selectionRequired: Bool = false, selectionDeadline: Date? = nil) {
        self.owned = owned
        self.limit = limit
        self.selectionRequired = selectionRequired
        self.selectionDeadline = selectionDeadline
    }
}

/// A `/users/search` item: public fields only. Follower and following lists (and a notification's
/// actor) also say how the viewer and the user follow each other.
public struct UserSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var displayName: String?
    public var avatarUrl: String?
    /// Whether the viewer follows this user / this user follows the viewer; nil where the API doesn't say.
    public var isFollowing: Bool?
    public var followsYou: Bool?
    /// A community account (a group's page), shown with a badge.
    public var isCommunity: Bool

    public init(
        id: String, username: String, displayName: String? = nil, avatarUrl: String? = nil,
        isFollowing: Bool? = nil, followsYou: Bool? = nil, isCommunity: Bool = false
    ) {
        self.isCommunity = isCommunity
        self.isFollowing = isFollowing
        self.followsYou = followsYou
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

/// The owner of an Invite-only Poll, shown on its Invitation link before the viewer can open it.
public struct PollOwner: Hashable, Sendable {
    public var username: String
    public var avatarUrl: String?

    public init(username: String, avatarUrl: String? = nil) {
        self.username = username
        self.avatarUrl = avatarUrl
    }
}

/// A private, reusable invite list. Only its owner ever sees it.
public struct UserGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var memberCount: Int

    public init(id: String, name: String, memberCount: Int) {
        self.id = id
        self.name = name
        self.memberCount = memberCount
    }
}

public let groupNameMax = 50

public struct GroupMember: Identifiable, Hashable, Sendable {
    public var id: String { person.key }
    public var person: Person
    public var addedAt: Date?
}

/// One page of a list endpoint. A nil `nextCursor` means the last page.
public struct CursorPage<Item: Sendable>: Sendable {
    public var items: [Item]
    public var nextCursor: String?

    public init(items: [Item], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public static var empty: CursorPage { CursorPage(items: [], nextCursor: nil) }
}

extension CursorPage: Equatable where Item: Equatable {}

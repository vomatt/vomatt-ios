import Foundation

/// GET /users/{username}. Fields the owner hides come back nil.
public struct UserProfile: Hashable, Sendable {
    public var username: String
    public var displayName: String?
    public var bio: String?
    public var avatarUrl: String?
    public var joinedAt: Date?
    public var totalPolls: Int
    public var totalVotes: Int
    public var location: String?
    public var points: Int?
    public var membershipLevel: String?

    public init(
        username: String, displayName: String? = nil, bio: String? = nil, avatarUrl: String? = nil,
        joinedAt: Date? = nil, totalPolls: Int = 0, totalVotes: Int = 0, location: String? = nil,
        points: Int? = nil, membershipLevel: String? = nil
    ) {
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.joinedAt = joinedAt
        self.totalPolls = totalPolls
        self.totalVotes = totalVotes
        self.location = location
        self.points = points
        self.membershipLevel = membershipLevel
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
    public var location: String?
    /// `yyyy-MM-dd`; once set it can be changed but not cleared.
    public var birthday: String?
    public var points: Int
    public var membershipLevel: String?
    public var joinedAt: Date?
    public var totalPolls: Int
    public var totalVotes: Int
    public var visibilitySettings: [String: Bool]
    /// Whether a first Ballot is Anonymous unless the voter says otherwise.
    public var anonymousBallotByDefault: Bool

    public init(
        id: String, username: String, email: String? = nil, displayName: String? = nil, bio: String? = nil,
        avatarUrl: String? = nil, firstName: String? = nil, lastName: String? = nil, location: String? = nil,
        birthday: String? = nil, points: Int = 0,
        membershipLevel: String? = nil, joinedAt: Date? = nil, totalPolls: Int = 0, totalVotes: Int = 0, visibilitySettings: [String: Bool] = [:],
        anonymousBallotByDefault: Bool = false
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.bio = bio
        self.avatarUrl = avatarUrl
        self.firstName = firstName
        self.lastName = lastName
        self.location = location
        self.birthday = birthday
        self.points = points
        self.membershipLevel = membershipLevel
        self.joinedAt = joinedAt
        self.totalPolls = totalPolls
        self.totalVotes = totalVotes
        self.visibilitySettings = visibilitySettings
        self.anonymousBallotByDefault = anonymousBallotByDefault
    }

    /// The profile as visitors see it, honoring the owner's visibility switches.
    public var asPublicProfile: UserProfile {
        UserProfile(
            username: username,
            displayName: displayName,
            bio: bio,
            avatarUrl: avatarUrl,
            joinedAt: joinedAt,
            totalPolls: totalPolls,
            totalVotes: totalVotes,
            location: visibilitySettings["location"] == true ? location : nil,
            points: visibilitySettings["points"] == true ? points : nil,
            membershipLevel: visibilitySettings["membershipLevel"] == true ? membershipLevel : nil
        )
    }
}

/// A `/users/search` item: public fields only.
public struct UserSummary: Identifiable, Hashable, Sendable {
    public let id: String
    public var username: String
    public var displayName: String?
    public var avatarUrl: String?

    public init(id: String, username: String, displayName: String? = nil, avatarUrl: String? = nil) {
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

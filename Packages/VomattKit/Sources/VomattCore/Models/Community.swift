import Foundation

/// A member's role in a community account, most powerful first (the web's `COMMUNITY_ROLES`).
/// The raw value is the API's, and the suffix of its `communities.roles.*` string.
public enum CommunityRole: String, CaseIterable, Sendable {
    case owner = "OWNER"
    case admin = "ADMIN"
    case chiefEditor = "CHIEF_EDITOR"
    case editor = "EDITOR"
    case analyst = "ANALYST"
}

/// A community account the viewer belongs to, with their role in it (GET /users/me/communities).
public struct MyCommunity: Identifiable, Hashable, Sendable {
    /// The community account's user id.
    public let id: String
    public var username: String
    public var displayName: String?
    public var avatarUrl: String?
    public var role: CommunityRole
    /// Readable, but it can't post or change anything until an owner unlocks it.
    public var isLocked: Bool

    public init(
        id: String, username: String, displayName: String? = nil, avatarUrl: String? = nil,
        role: CommunityRole, isLocked: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.role = role
        self.isLocked = isLocked
    }
}

/// An invitation to join a community account, as its invitee sees it on the invitation's own page.
public struct CommunityInvitationDetail: Identifiable, Hashable, Sendable {
    public let id: String
    /// The role the viewer gets on joining.
    public var role: CommunityRole
    public var expiresAt: Date
    public var community: UserSummary
    /// The member who sent it; nil once their account is deleted.
    public var inviter: UserSummary?
    /// The community account is locked: the invitation can be declined, but accepting fails with
    /// `community.locked` until an owner unlocks it.
    public var isLocked: Bool
    /// The viewer already belongs to it: accepting keeps their current role.
    public var isMember: Bool

    public init(
        id: String, role: CommunityRole, expiresAt: Date, community: UserSummary, inviter: UserSummary? = nil,
        isLocked: Bool = false, isMember: Bool = false
    ) {
        self.id = id
        self.role = role
        self.expiresAt = expiresAt
        self.community = community
        self.inviter = inviter
        self.isLocked = isLocked
        self.isMember = isMember
    }
}

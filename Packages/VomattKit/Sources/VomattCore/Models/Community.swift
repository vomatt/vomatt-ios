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

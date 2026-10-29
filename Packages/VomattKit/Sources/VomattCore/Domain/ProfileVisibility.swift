import Foundation

/// Who sees each profile detail (the web's `features/account/visibility.ts`).
public enum ProfileVisibility {
    /// Profile fields other people can see once their owner allows it (the API's visibility keys).
    public static let fields = ["displayName", "bio", "firstName", "lastName", "location", "points", "membershipLevel"]

    /// Public until the owner turns them off; the rest stay hidden until turned on (the API's defaults).
    private static let publicByDefault: Set = ["displayName", "bio"]

    /// Whether visitors see `field`, falling back to the API's default when the setting is missing.
    public static func isPublic(_ visibility: [String: Bool], _ field: String) -> Bool {
        visibility[field] ?? publicByDefault.contains(field)
    }

    /// The settings that differ from `saved`, as `PATCH /users/me/visibility` takes them; empty when none do.
    public static func changes(saved: [String: Bool], next: [String: Bool]) -> [String: Bool] {
        Dictionary(uniqueKeysWithValues: fields
            .filter { isPublic(next, $0) != isPublic(saved, $0) }
            .map { ($0, isPublic(next, $0)) })
    }
}

public extension MyProfile {
    /// How many of the visibility fields visitors see: "3 of 7 shown".
    var shownFieldCount: Int {
        ProfileVisibility.fields.filter { ProfileVisibility.isPublic(visibilitySettings, $0) }.count
    }

    /// Hidden fields that have a value; the owner's header marks each with the lock.
    var hiddenFields: Set<String> {
        Set(ProfileVisibility.fields.filter { !ProfileVisibility.isPublic(visibilitySettings, $0) && hasValue($0) })
    }

    /// The profile with every field, as its owner sees it.
    var asOwnProfile: UserProfile {
        UserProfile(
            id: id, username: username, displayName: displayName, bio: bio, avatarUrl: avatarUrl, joinedAt: joinedAt,
            totalPolls: totalPolls, totalVotes: totalVotes, location: location, points: points,
            membershipLevel: membershipLevel, followersCount: followersCount, followingCount: followingCount
        )
    }

    private func hasValue(_ field: String) -> Bool {
        let text: String? = switch field {
        case "displayName": displayName
        case "bio": bio
        case "firstName": firstName
        case "lastName": lastName
        case "location": location
        case "membershipLevel": membershipLevel
        case "points": String(points)
        default: nil
        }
        return text?.isEmpty == false
    }
}

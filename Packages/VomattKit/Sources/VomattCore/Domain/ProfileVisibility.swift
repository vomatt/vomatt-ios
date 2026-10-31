import Foundation

/// Who sees each profile detail (the web's `features/account/visibility.ts`).
public enum ProfileVisibility {
    /// Profile fields other people can see once their owner allows it: the API's visibility keys this app
    /// shows. Location, points and membership level are left out, since no page shows them.
    public static let fields = ["displayName", "bio", "firstName", "lastName"]

    /// One per Edit profile setting; the real name shows when either half does.
    public static let settings = [["displayName"], ["bio"], ["firstName", "lastName"]]

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
    /// How many of the Edit profile settings visitors see: "2 of 3 shown".
    var shownSettingCount: Int {
        ProfileVisibility.settings.filter { $0.contains { ProfileVisibility.isPublic(visibilitySettings, $0) } }.count
    }

    /// Hidden fields that have a value; the owner's header marks each with the lock.
    var hiddenFields: Set<String> {
        Set(ProfileVisibility.fields.filter { !ProfileVisibility.isPublic(visibilitySettings, $0) && hasValue($0) })
    }

    /// The profile with every field, as its owner sees it.
    var asOwnProfile: UserProfile {
        UserProfile(
            id: id, username: username, displayName: displayName, firstName: firstName, lastName: lastName, bio: bio,
            avatarUrl: avatarUrl, joinedAt: joinedAt, totalPolls: totalPolls, totalVotes: totalVotes,
            followersCount: followersCount, followingCount: followingCount
        )
    }

    private func hasValue(_ field: String) -> Bool {
        let text: String? = switch field {
        case "displayName": displayName
        case "bio": bio
        case "firstName": firstName
        case "lastName": lastName
        default: nil
        }
        return text?.isEmpty == false
    }
}

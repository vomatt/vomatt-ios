import Foundation

/// The API's username rule (`UpdateProfileRequest.username`), reserved names included.
public enum Username {
    public static let maxLength = 50

    public static let reserved: Set<String> = [
        "search", "account", "explore", "login", "notifications", "poll", "sanity",
        "api", "me", "my", "admin", "settings",
    ]

    public static func isValid(_ username: String) -> Bool {
        guard !reserved.contains(username), (3...maxLength).contains(username.count) else { return false }
        return username.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }

    /// Whether `username` is the viewer's own; case-insensitive, as profile lookups may be.
    public static func isOwn(_ username: String, me: String?) -> Bool {
        guard let me else { return false }
        return me.lowercased() == username.lowercased()
    }
}

/// The web's `emailSchema`: a trimmed, plausible address.
public enum Email {
    public static func normalize(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isValid(_ email: String) -> Bool {
        let value = normalize(email)
        guard let at = value.firstIndex(of: "@"), at != value.startIndex else { return false }
        let domain = value[value.index(after: at)...]
        return !value.contains(" ") && domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
            && value.filter { $0 == "@" }.count == 1
    }
}

import Foundation

/// People the viewer blocked on this device: their polls and comments are hidden
/// (App Review guideline 1.2). Signed in, the API holds the real list and `AppModel` mirrors it
/// here; signed out, this is the only copy.
public struct BlockList: Sendable {
    private let key: String
    private let suiteName: String?

    public init(key: String = "vomatt_blocked_users", suiteName: String? = nil) {
        self.key = key
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// Lowercased usernames, sorted.
    public func usernames() -> [String] {
        (defaults.stringArray(forKey: key) ?? []).sorted()
    }

    public func contains(_ username: String?) -> Bool {
        guard let username else { return false }
        return usernames().contains(username.lowercased())
    }

    @discardableResult
    public func block(_ username: String) -> [String] {
        write(Set(usernames()).union([username.lowercased()]))
    }

    @discardableResult
    public func unblock(_ username: String) -> [String] {
        write(Set(usernames()).subtracting([username.lowercased()]))
    }

    private func write(_ names: Set<String>) -> [String] {
        let sorted = names.sorted()
        defaults.set(sorted, forKey: key)
        return sorted
    }
}

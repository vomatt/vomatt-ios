import Foundation

/// "Followed by @jtan and 2 others you follow": the people the viewer follows who follow this person
/// (the web's `MutualFollowersLine`).
public struct MutualFollowersLine: Equatable, Sendable {
    /// Up to two people, in the order the text names them; each gets a small avatar.
    public let shown: [UserSummary]
    public let text: String

    /// Nil signed out, on the viewer's own profile, or when no one they follow follows this person.
    public init?(count: Int?, preview: [UserSummary], t: Localizer) {
        let count = count ?? 0
        let shown = Array(preview.prefix(min(max(count, 0), 2)))
        guard let first = shown.first else { return nil }
        let others = count - 1
        self.shown = shown
        if others == 0 {
            text = t("profile.mutualsOne", ["name": first.username])
        } else if others == 1, shown.count > 1 {
            text = t("profile.mutualsTwo", ["name": first.username, "other": shown[1].username])
        } else {
            text = t.count("profile.mutualsMore", others, ["name": first.username])
        }
    }
}

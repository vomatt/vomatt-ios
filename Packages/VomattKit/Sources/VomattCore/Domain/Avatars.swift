import Foundation

/// The bot cast (port of vomatt-web `features/avatars/catalog.ts`): 60 characters
/// in six families (`families` mirrors the web's `BOT_FAMILIES`, kept for re-syncing). A chosen bot is stored in `avatarUrl` as `bot:<kind>`.
public enum Avatars {
    public enum Tint: String, Sendable {
        case sand, stone, green, sky, peach, lavender
    }

    public static let families: [(name: String, kinds: [String])] = [
        ("bites", ["boba", "bao", "oolong", "su", "ice", "youtiao", "chip", "tower", "lumen"]),
        ("guardians", ["mazu", "tudi", "yuelao", "qiye", "baye", "long", "denglong", "jiaobei", "xiang"]),
        ("visitors", ["gray", "nordic", "reptile", "mantis", "anu", "tallwhite", "moth", "cyclops", "trio"]),
        ("animals", ["bear", "magpie", "pangolin", "shihu", "macaque", "deer", "pheasant", "flyfish", "dog"]),
        ("cats", ["fold", "munchkin", "chinchilla", "mainecoon", "siamese", "orange", "tuxedo", "calico", "sphynx", "ragdoll", "british", "bengal"]),
        ("dogs", ["shiba", "corgi", "golden", "husky", "pug", "dachshund", "poodle", "frenchie", "beagle", "collie", "dalmatian", "labrador"]),
    ]

    public static let kinds: [String] = families.flatMap(\.kinds)

    public static let tints: [String: Tint] = [
        "boba": .sand, "bao": .stone, "oolong": .green, "su": .sand, "ice": .sky,
        "youtiao": .sand, "chip": .sky, "tower": .sky, "lumen": .peach,
        "mazu": .sky, "tudi": .sand, "yuelao": .lavender, "qiye": .stone, "baye": .peach,
        "long": .peach, "denglong": .peach, "jiaobei": .peach, "xiang": .sand,
        "gray": .stone, "nordic": .sky, "reptile": .green, "mantis": .peach, "anu": .sand, "tallwhite": .lavender,
        "moth": .lavender, "cyclops": .sky, "trio": .green,
        "bear": .stone, "magpie": .sky, "pangolin": .sand, "shihu": .peach, "macaque": .lavender, "deer": .green,
        "pheasant": .sand, "flyfish": .sky, "dog": .sand,
        "fold": .stone, "munchkin": .peach, "chinchilla": .lavender, "mainecoon": .stone, "siamese": .sky, "orange": .sand,
        "tuxedo": .stone, "calico": .peach, "sphynx": .peach, "ragdoll": .sky, "british": .stone, "bengal": .sand,
        "shiba": .sand, "corgi": .sand, "golden": .sand, "husky": .sky, "pug": .sand, "dachshund": .sand,
        "poodle": .peach, "frenchie": .stone, "beagle": .peach, "collie": .stone, "dalmatian": .stone, "labrador": .sand,
    ]

    private static let prefix = "bot:"

    public static func avatarUrl(for kind: String) -> String { prefix + kind }

    public static func isKind(_ value: String) -> Bool { tints[value] != nil }

    /// No character: the plain account icon, stored as `bot:none`. Never a default.
    public static let noBot = "none"

    /// What a user can choose: one of the cast, or no character.
    public static func isChoice(_ value: String) -> Bool { value == noBot || isKind(value) }

    /// A plain account icon: `bot:none` (no character), or a bot since retired from the cast.
    public static func isNone(_ avatarUrl: String?) -> Bool {
        guard let avatarUrl, avatarUrl.hasPrefix(prefix) else { return false }
        return parse(avatarUrl) == nil
    }

    /// The kind in a `bot:<kind>` value; nil for anything else, including an unknown kind.
    public static func parse(_ avatarUrl: String?) -> String? {
        guard let avatarUrl, avatarUrl.hasPrefix(prefix) else { return nil }
        let kind = String(avatarUrl.dropFirst(prefix.count))
        return isKind(kind) ? kind : nil
    }

    /// An uploaded photo: `/api/avatars/<id>.jpg`, a path on the API origin (not a full URL).
    public static func isUploaded(_ avatarUrl: String?) -> Bool {
        guard let avatarUrl else { return false }
        return avatarUrl.hasPrefix(uploadedPrefix) && avatarUrl.count > uploadedPrefix.count
    }

    /// Where to load an uploaded photo from: the path joined to the API origin; nil for a bot or no avatar.
    public static func uploadedURL(_ avatarUrl: String?, apiURL: URL) -> URL? {
        guard let avatarUrl, isUploaded(avatarUrl) else { return nil }
        return URL(string: avatarUrl, relativeTo: apiURL)?.absoluteURL
    }

    private static let uploadedPrefix = "/api/avatars/"

    /// Defaults are picked from the original cast of 72, so usernames keep their character
    /// as the cast shrinks. These are the slots of the characters since retired, ascending.
    private static let originalCastSize: UInt32 = 72
    private static let retiredSlots: [UInt32] = [4, 7, 8, 17, 20, 23, 31, 33, 34, 43, 44, 46]

    /// The bot a user gets until they choose one: picked from the username (FNV-1a over
    /// code points, matching the web), so everyone sees the same character for them.
    public static func defaultKind(for username: String) -> String {
        var hash: UInt32 = 0x811c_9dc5
        for scalar in username.lowercased().unicodeScalars {
            hash ^= scalar.value
            hash = hash &* 0x0100_0193
        }
        let slot = hash % originalCastSize
        if retiredSlots.contains(slot) { return kinds[Int(hash % UInt32(kinds.count))] }
        return kinds[Int(slot) - retiredSlots.filter { $0 < slot }.count]
    }

    /// What to draw: the bot they chose, `noBot` if they chose no character or one since retired,
    /// else their username's bot. Image URLs are ignored.
    public static func resolve(username: String, avatarUrl: String?) -> String {
        if avatarUrl?.hasPrefix(prefix) == true { return parse(avatarUrl) ?? noBot }
        return defaultKind(for: username)
    }
}

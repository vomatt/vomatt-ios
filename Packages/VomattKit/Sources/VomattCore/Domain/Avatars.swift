import Foundation

/// The bot cast (port of vomatt-web `features/avatars/catalog.ts`): 72 characters
/// in six families of twelve. A chosen bot is stored in `avatarUrl` as `bot:<kind>`.
public enum Avatars {
    public enum Tint: String, Sendable {
        case sand, stone, green, sky, peach, lavender
    }

    public static let families: [(name: String, kinds: [String])] = [
        ("bites", ["boba", "bao", "oolong", "su", "egg", "ice", "youtiao", "tofu", "sausage", "chip", "tower", "lumen"]),
        ("guardians", ["mazu", "tudi", "yuelao", "qiye", "baye", "shi", "long", "denglong", "ding", "jiaobei", "xiang", "banyan"]),
        ("visitors", ["gray", "nordic", "reptile", "mantis", "anu", "tallwhite", "moth", "blob", "cyclops", "probe", "saucer", "trio"]),
        ("animals", ["bear", "magpie", "pangolin", "shihu", "macaque", "deer", "pheasant", "firefly", "crab", "flyfish", "turtle", "dog"]),
        ("cats", ["fold", "munchkin", "chinchilla", "mainecoon", "siamese", "orange", "tuxedo", "calico", "sphynx", "ragdoll", "british", "bengal"]),
        ("dogs", ["shiba", "corgi", "golden", "husky", "pug", "dachshund", "poodle", "frenchie", "beagle", "collie", "dalmatian", "labrador"]),
    ]

    public static let kinds: [String] = families.flatMap(\.kinds)

    public static let tints: [String: Tint] = [
        "boba": .sand, "bao": .stone, "oolong": .green, "su": .sand, "egg": .peach, "ice": .sky,
        "youtiao": .sand, "tofu": .stone, "sausage": .peach, "chip": .sky, "tower": .sky, "lumen": .peach,
        "mazu": .sky, "tudi": .sand, "yuelao": .lavender, "qiye": .stone, "baye": .peach, "shi": .stone,
        "long": .peach, "denglong": .peach, "ding": .sand, "jiaobei": .peach, "xiang": .sand, "banyan": .green,
        "gray": .stone, "nordic": .sky, "reptile": .green, "mantis": .peach, "anu": .sand, "tallwhite": .lavender,
        "moth": .lavender, "blob": .green, "cyclops": .sky, "probe": .stone, "saucer": .sky, "trio": .green,
        "bear": .stone, "magpie": .sky, "pangolin": .sand, "shihu": .peach, "macaque": .lavender, "deer": .green,
        "pheasant": .sand, "firefly": .green, "crab": .peach, "flyfish": .sky, "turtle": .sky, "dog": .sand,
        "fold": .stone, "munchkin": .peach, "chinchilla": .lavender, "mainecoon": .stone, "siamese": .sky, "orange": .sand,
        "tuxedo": .stone, "calico": .peach, "sphynx": .peach, "ragdoll": .sky, "british": .stone, "bengal": .sand,
        "shiba": .sand, "corgi": .sand, "golden": .sand, "husky": .sky, "pug": .sand, "dachshund": .sand,
        "poodle": .peach, "frenchie": .stone, "beagle": .peach, "collie": .stone, "dalmatian": .stone, "labrador": .sand,
    ]

    private static let prefix = "bot:"

    public static func avatarUrl(for kind: String) -> String { prefix + kind }

    public static func isKind(_ value: String) -> Bool { tints[value] != nil }

    /// `bot:none`: the user picked no character and gets a plain account icon.
    public static func isNone(_ avatarUrl: String?) -> Bool { avatarUrl == prefix + "none" }

    /// The kind in a `bot:<kind>` value; nil for anything else, including an unknown kind.
    public static func parse(_ avatarUrl: String?) -> String? {
        guard let avatarUrl, avatarUrl.hasPrefix(prefix) else { return nil }
        let kind = String(avatarUrl.dropFirst(prefix.count))
        return isKind(kind) ? kind : nil
    }

    /// The bot a user gets until they choose one: picked from the username (FNV-1a over
    /// code points, matching the web), so everyone sees the same character for them.
    public static func defaultKind(for username: String) -> String {
        var hash: UInt32 = 0x811c_9dc5
        for scalar in username.lowercased().unicodeScalars {
            hash ^= scalar.value
            hash = hash &* 0x0100_0193
        }
        return kinds[Int(hash % UInt32(kinds.count))]
    }

    /// The bot to draw: the one they chose, else their username's. Image URLs are ignored.
    public static func resolve(username: String, avatarUrl: String?) -> String {
        parse(avatarUrl) ?? defaultKind(for: username)
    }
}

import Foundation

/// The API serves only UUID poll ids. Signed out, it answers any other id with 401 instead of 404, so
/// a link with a malformed id is not-found before it reaches the API (the web's poll page `POLL_ID`).
/// Links carry the UUID's 128 bits in base62 (vomatt-web `src/features/polls/shortId.ts`).
public enum PollID {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    public static func isValid(_ id: String) -> Bool {
        id.wholeMatch(of: #/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/#.ignoresCase()) != nil
    }

    /// The Poll id a link's path segment stands for: a UUID as is, or the UUID behind a short id.
    public static func fromLink(_ segment: String) -> String? {
        isValid(segment) ? segment : fromShortId(segment)
    }

    /// A Poll's UUID as base62 for its link: 21 or 22 characters instead of 36. Nil when `uuid` isn't one.
    public static func shortId(_ uuid: String) -> String? {
        guard isValid(uuid), let parsed = UUID(uuidString: uuid) else { return nil }
        var bytes = withUnsafeBytes(of: parsed.uuid) { Array($0) }
        var out: [Character] = []
        repeat {
            var remainder = 0
            for i in bytes.indices {
                let value = remainder << 8 | Int(bytes[i])
                bytes[i] = UInt8(value / 62)
                remainder = value % 62
            }
            out.append(alphabet[remainder])
        } while bytes.contains { $0 != 0 }
        return String(out.reversed())
    }

    /// The UUID a short id stands for, or nil when it isn't one `shortId` would write (so each Poll has one link).
    public static func fromShortId(_ shortId: String) -> String? {
        guard (1...22).contains(shortId.count) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        for char in shortId {
            guard let digit = alphabet.firstIndex(of: char) else { return nil }
            var carry = digit
            for i in bytes.indices.reversed() {
                let value = Int(bytes[i]) * 62 + carry
                bytes[i] = UInt8(value & 0xFF)
                carry = value >> 8
            }
            guard carry == 0 else { return nil }
        }
        let uuid = UUID(uuid: bytes.withUnsafeBytes { $0.load(as: uuid_t.self) }).uuidString.lowercased()
        return self.shortId(uuid) == shortId ? uuid : nil
    }
}

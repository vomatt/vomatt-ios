import Foundation

/// The `@handle` the caret is in: where its `@` sits (in Characters) and what follows it up to the caret, lowercased.
public struct ActiveMention: Equatable, Sendable {
    public let start: Int
    public let term: String

    public init(start: Int, term: String) {
        self.start = start
        self.term = term
    }
}

/// Suggesting people while an `@handle` is typed (the web's `MentionTextarea`).
public enum Mention {
    public static let maxSuggestions = 6

    private static func isHandleChar(_ c: Character) -> Bool {
        c == "_" || (c.isASCII && (c.isLetter || c.isNumber))
    }

    /// The API's mention rule: an `@` not preceded by a letter or digit of any script, or `_`.
    public static func active(in text: String, caret: Int) -> ActiveMention? {
        let chars = Array(text.prefix(caret))
        var at = chars.count
        while at > 0, isHandleChar(chars[at - 1]) { at -= 1 }
        let termLength = chars.count - at
        guard at > 0, chars[at - 1] == "@", termLength <= Username.maxLength else { return nil }
        let start = at - 1
        if start > 0 {
            let before = chars[start - 1]
            if before == "_" || before.isLetter || before.isNumber { return nil }
        }
        return ActiveMention(start: start, term: String(chars[at...]).lowercased())
    }

    /// Replaces the whole handle the caret is in (also what follows the caret) with `@username `.
    public static func insert(_ username: String, into text: String, replacing mention: ActiveMention) -> (text: String, caret: Int) {
        let chars = Array(text)
        var end = mention.start + 1
        while end < chars.count, isHandleChar(chars[end]) { end += 1 }
        let inserted = "@\(username) "
        var after = chars[end...]
        if after.first == " " { after = after.dropFirst() }
        return (String(chars[..<mention.start]) + inserted + String(after), mention.start + inserted.count)
    }

    /// What the list shows from a lookup: never the viewer, at most `maxSuggestions`.
    public static func suggestions(_ users: [UserSummary], viewer: String) -> [UserSummary] {
        Array(users.filter { $0.username.lowercased() != viewer.lowercased() }.prefix(maxSuggestions))
    }
}

import Foundation

/// The name a profile leads with, from the web's `features/profiles/name.ts`: the real name, then the
/// display name after it when both are set; otherwise whichever one is set, falling back to the username.
public struct ProfileName: Equatable, Sendable {
    public let primary: String
    /// The display name beside a real name; nil when there is none or it repeats the real name.
    public let secondary: String?

    init(primary: String, secondary: String?) {
        self.primary = primary
        self.secondary = secondary
    }

    public init(username: String, displayName: String? = nil, firstName: String? = nil, lastName: String? = nil) {
        let real = Self.realName(firstName: firstName, lastName: lastName)
        let display = displayName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        primary = real ?? display ?? username
        if let real, let display, display.lowercased() != real.lowercased() {
            secondary = display
        } else {
            secondary = nil
        }
    }

    /// First and last name as one string; a name written in Han or Hangul (both parts) reads family name
    /// first with no space (陳小明, 김민준). Nil when neither is set.
    public static func realName(firstName: String?, lastName: String?) -> String? {
        let first = firstName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        let last = lastName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
        guard let first, let last else { return first ?? last }
        return isFamilyFirst(first) && isFamilyFirst(last) ? last + first : "\(first) \(last)"
    }

    // Chinese, Japanese kanji and Korean names put the family name first
    private static func isFamilyFirst(_ text: String) -> Bool {
        text.contains(#/[\p{Script=Han}\p{Script=Hangul}]/#)
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// A new account's real name from the sign-up step (the web's `profileSchema` and `submitProfile`).
public struct SignUpName: Equatable, Sendable {
    /// The backend caps each name at 50 characters.
    public static let maxLength = 50

    public let firstName: String
    /// Nil when blank: sending it empty would clear it. Not everyone has one.
    public let lastName: String?

    /// Nil without a first name, which the step requires.
    public init?(firstName: String, lastName: String) {
        guard let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty else { return nil }
        self.firstName = first
        self.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
    }
}

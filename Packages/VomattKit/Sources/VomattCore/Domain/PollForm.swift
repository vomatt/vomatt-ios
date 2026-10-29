import Foundation

/// People picked by username or email, and Groups whose members are copied in.
public struct InviteeSelection: Codable, Hashable, Sendable {
    public struct User: Codable, Hashable, Identifiable, Sendable {
        public let id: String
        public var username: String
        public var avatarUrl: String?

        public init(id: String, username: String, avatarUrl: String? = nil) {
            self.id = id
            self.username = username
            self.avatarUrl = avatarUrl
        }
    }

    public struct PickedGroup: Codable, Hashable, Identifiable, Sendable {
        public let id: String
        public var name: String
        public var memberCount: Int

        public init(id: String, name: String, memberCount: Int) {
            self.id = id
            self.name = name
            self.memberCount = memberCount
        }
    }

    public var users: [User] = []
    public var emails: [String] = []
    public var groups: [PickedGroup] = []

    public init(users: [User] = [], emails: [String] = [], groups: [PickedGroup] = []) {
        self.users = users
        self.emails = emails
        self.groups = groups
    }

    public var isEmpty: Bool { users.isEmpty && emails.isEmpty && groups.isEmpty }

    public var input: InviteesInput {
        InviteesInput(userIds: users.map(\.id), emails: emails, groupIds: groups.map(\.id))
    }
}

/// The poll creator's values (port of `PollCreator/formSchema.ts`). Codable so drafts can be saved.
public struct PollForm: Codable, Hashable, Sendable {
    public var title: String
    public var description: String
    public var options: [String]
    /// nil opens the Poll now.
    public var startTime: Date?
    public var endTime: Date?
    public var voterVisibility: VoterVisibility
    public var audience: Audience
    /// nil when editing a Poll that is already Invite-only: its Invitees are managed on the Poll.
    public var invitees: InviteeSelection?

    public init(
        title: String = "", description: String = "", options: [String] = ["", ""],
        startTime: Date? = nil, endTime: Date?, voterVisibility: VoterVisibility = .owner,
        audience: Audience = .public, invitees: InviteeSelection? = InviteeSelection()
    ) {
        self.title = title
        self.description = description
        self.options = options
        self.startTime = startTime
        self.endTime = endTime
        self.voterVisibility = voterVisibility
        self.audience = audience
        self.invitees = invitees
    }

    /// A blank form ending in three days, like the web's default preset.
    public static func empty(now: Date = .now) -> PollForm {
        PollForm(endTime: now.addingTimeInterval(3 * 24 * 3600))
    }

    public init(poll: Poll) {
        self.init(
            title: poll.title,
            description: poll.description ?? "",
            options: poll.options.map(\.text),
            startTime: poll.startTime,
            endTime: poll.endTime,
            voterVisibility: poll.voterVisibility ?? .owner,
            audience: poll.audience ?? .public,
            invitees: poll.audience == .inviteOnly ? nil : InviteeSelection()
        )
    }

    public enum Field: Hashable, Sendable {
        case title, option(Int), endTime, invitees
    }

    /// Validation errors as translation keys (the web's `pollCreator.errors.*`).
    public func errors(now: Date = .now) -> [Field: String] {
        var errors: [Field: String] = [:]
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { errors[.title] = "pollCreator.errors.titleRequired" }
        else if title.count > pollTitleMax { errors[.title] = "pollCreator.errors.titleTooLong" }
        // Two options with the same text split one opinion into two counts
        var seen = Set<String>()
        for (index, option) in options.enumerated() {
            let key = option.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key.isEmpty {
                errors[.option(index)] = "pollCreator.errors.optionRequired"
            } else if !seen.insert(key).inserted {
                errors[.option(index)] = "pollCreator.errors.optionDuplicate"
            }
        }
        if let endTime {
            if endTime <= (startTime ?? now) { errors[.endTime] = "pollCreator.errors.endBeforeStart" }
        } else {
            errors[.endTime] = "pollCreator.errors.endRequired"
        }
        if audience == .inviteOnly, let invitees, invitees.isEmpty {
            errors[.invitees] = "pollCreator.errors.inviteesRequired"
        }
        return errors
    }

    /// Each distinct problem with the options once, in the order they first appear: one line under the list.
    public static func optionMessages(_ errors: [Field: String], count: Int) -> [String] {
        var messages: [String] = []
        for index in 0..<count {
            if let message = errors[.option(index)], !messages.contains(message) { messages.append(message) }
        }
        return messages
    }

    public var canAddOption: Bool {
        options.count < pollOptionsLimit && options.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The first blank option: Add option goes there instead of adding another.
    public var firstEmptyOption: Int? {
        options.firstIndex { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The end-time presets. Each counts from the opening time, or from now when it opens now.
    public enum EndPreset: String, CaseIterable, Sendable {
        case hour = "1h", day = "24h", threeDays = "3d", week = "1w"

        public var duration: TimeInterval {
            switch self {
            case .hour: 3600
            case .day: 24 * 3600
            case .threeDays: 3 * 24 * 3600
            case .week: 7 * 24 * 3600
            }
        }

        public var labelKey: String { "pollCreator.preset\(rawValue)" }
    }

    public mutating func apply(_ preset: EndPreset, now: Date = .now) {
        endTime = (startTime ?? now).addingTimeInterval(preset.duration)
    }

    /// The question as one line: pasted line breaks become spaces.
    public static func singleLine(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func input(now: Date = .now) -> PollInput {
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return PollInput(
            title: Self.singleLine(title),
            description: description.isEmpty ? nil : description,
            options: options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            startTime: startTime ?? now,
            endTime: endTime ?? now,
            voterVisibility: voterVisibility,
            audience: audience,
            invitees: audience == .inviteOnly ? invitees?.input : nil
        )
    }

    public var visibilityLevel: VisibilityLevel { Self.visibilityLevel(voterVisibility, audience: audience) }

    /// How a choice reads for this Audience: on an Invite-only Poll "signed in" is everyone invited.
    public static func visibilityLevel(_ visibility: VoterVisibility, audience: Audience) -> VisibilityLevel {
        switch visibility {
        case .nobody: .nobody
        case .owner: .owner
        case .signedIn: audience == .inviteOnly ? .invited : .signedIn
        }
    }
}

/// A saved, unpublished Poll. Drafts stay on the device; they never reach the API.
public struct PollDraft: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var savedAt: Date
    public var form: PollForm

    public init(id: String = UUID().uuidString, savedAt: Date = .now, form: PollForm) {
        self.id = id
        self.savedAt = savedAt
        self.form = form
    }

    /// "Saved yesterday · 3 options · no end date yet"; blank option fields aren't options yet.
    public func meta(t: Localizer, dates: DateFormatting, now: Date = .now) -> String {
        let options = form.options.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return [
            t("myPolls.draftSavedAt", ["date": dates.pollDay(savedAt, now: now)]),
            options > 0 ? t.count("myPolls.draftOptions", options) : nil,
            form.endTime == nil ? t("myPolls.draftNoEnd") : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Drafts in `UserDefaults`, newest first.
public struct DraftStore: Sendable {
    private let key: String
    private let suiteName: String?

    public init(key: String = "vomatt_poll_drafts", suiteName: String? = nil) {
        self.key = key
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public func list() -> [PollDraft] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PollDraft].self, from: data)) ?? []
    }

    /// Saves a new draft, or overwrites the one with the same id.
    @discardableResult
    public func save(_ form: PollForm, id: String? = nil) -> PollDraft {
        let draft = PollDraft(id: id ?? UUID().uuidString, form: form)
        write([draft] + list().filter { $0.id != draft.id })
        return draft
    }

    @discardableResult
    public func delete(_ id: String) -> [PollDraft] {
        let drafts = list().filter { $0.id != id }
        write(drafts)
        return drafts
    }

    private func write(_ drafts: [PollDraft]) {
        if let data = try? JSONEncoder().encode(drafts) { defaults.set(data, forKey: key) }
    }
}

import SwiftUI
import VomattCore

/// Settings, pushed from the gear on the profile (the web's `/settings`): Voting, Notifications,
/// Appearance and language, Privacy and safety, Account, then Delete account and the legal links.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            if let me = app.me {
                AccountSettings(profile: me)
                    .pageColumn(768)
                    .padding(.vertical, 24)
            }
        }
        .canvas()
        .navigationTitle(app.t("navigation.settings"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Invite lists on a screen of their own, opened from Settings.
struct InviteListsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            GroupsPanel()
                .pageColumn(768)
                .padding(.vertical, 24)
        }
        .canvas()
        .navigationTitle(app.t("account.tabGroups"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The app's light or dark look; Auto follows the system (the web's theme choice).
enum ThemeChoice: String, CaseIterable {
    case system, light, dark

    static let storageKey = "theme"

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A titled run of cards (the web's settings `Section`).
private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(text: title)
            content()
        }
    }
}

/// A row's title and the muted line under it (the web's `RowText`).
private struct RowText: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.vm(15, .medium)).foregroundStyle(Tokens.foreground)
            if let detail {
                Text(detail).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The hairline between rows of a settings card.
private struct RowDivider: View {
    var body: some View { Rectangle().fill(Tokens.border).frame(height: 1) }
}

private extension View {
    /// A settings card row's inset and height.
    func settingsRow() -> some View {
        padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 60)
    }
}

/// A row that opens something: its text, an optional value, and a chevron (or an outward arrow).
private struct NavigationRow: View {
    let title: String
    var detail: String?
    var value: String?
    var monoValue = false
    var external = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                RowText(title: title, detail: detail)
                if let value {
                    Text(value).font(monoValue ? .vmMono(14) : .vm(14)).foregroundStyle(Tokens.mutedForeground)
                }
                Image(systemName: external ? "arrow.up.right" : "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.mutedForeground)
            }
            .settingsRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The settings page itself (the web's `AccountSettings`).
private struct AccountSettings: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    let profile: MyProfile
    @AppStorage(ThemeChoice.storageKey) private var theme = ThemeChoice.system
    @State private var confirmingSignOut = false
    @State private var editingProfile = false
    /// How many invite lists the user has; nil until loaded or when they couldn't be.
    @State private var inviteListCount: Int?
    /// The last Ballot default the server confirmed; quick toggles can answer out of order.
    @State private var savedAnonymousDefault: Bool

    init(profile: MyProfile) {
        self.profile = profile
        _savedAnonymousDefault = State(initialValue: profile.anonymousBallotByDefault)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            SettingsSection(title: app.t("settings.voting")) {
                VStack(spacing: 0) {
                    Toggle(isOn: Binding(
                        get: { profile.anonymousBallotByDefault },
                        set: { value in Task { await toggleAnonymousDefault(value) } }
                    )) {
                        RowText(title: app.t("account.anonymousDefault"), detail: app.t("account.anonymousDefaultBody"))
                    }
                    .tint(Tokens.primary)
                    .settingsRow()
                    RowDivider()
                    NavigationRow(
                        title: app.t("account.tabGroups"),
                        detail: app.t("settings.inviteListsBody"),
                        value: inviteListCount.map { app.t.count("settings.inviteListCount", $0) },
                        monoValue: true
                    ) { app.push(.inviteLists) }
                }
                .card(padding: nil)
            }

            SettingsSection(title: app.t("notifications.title")) {
                NotificationSwitches()
            }

            SettingsSection(title: app.t("settings.appearanceAndLanguage")) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        RowText(title: app.t("settings.theme"))
                        Picker(app.t("settings.theme"), selection: $theme) {
                            Text(app.t("navigation.themeAuto")).tag(ThemeChoice.system)
                            Text(app.t("navigation.themeLight")).tag(ThemeChoice.light)
                            Text(app.t("navigation.themeDark")).tag(ThemeChoice.dark)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    .settingsRow()
                    RowDivider()
                    // The app's language follows the device; iOS Settings can set one for vomatt alone
                    NavigationRow(
                        title: app.t("settings.language"),
                        detail: app.t("ios.languageBody"),
                        value: languageName,
                        external: true
                    ) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                .card(padding: nil)
            }

            SettingsSection(title: app.t("settings.privacy")) {
                VStack(spacing: 0) {
                    NavigationRow(
                        title: app.t("account.privacyTitle"),
                        detail: app.t("settings.whatOthersSeeBody"),
                        value: app.t("settings.shownCount", ["shown": profile.shownFieldCount, "total": ProfileVisibility.fields.count])
                    ) { editingProfile = true }
                    RowDivider()
                    BlockedPeople().padding(16)
                }
                .card(padding: nil)
                FollowedPeople()
            }

            SettingsSection(title: app.t("settings.account")) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        RowText(title: app.t("account.signOutTitle"), detail: profile.email ?? profile.username)
                        Button(app.t("account.signOut")) { confirmingSignOut = true }.buttonStyle(.vm(.outline, size: .sm))
                    }
                    .settingsRow()
                    .confirmationDialog(app.t("account.signOut"), isPresented: $confirmingSignOut) {
                        Button(app.t("account.signOut"), role: .destructive) { Task { await app.signOut() } }
                    }
                    RowDivider()
                    PasskeysSection(service: app.service).padding(16)
                    RowDivider()
                    ExportDataRow()
                }
                .card(padding: nil)
                FeedbackRow().card(padding: nil)
            }

            // Kept apart, at the end, and quiet until opened
            DeleteAccountSection(username: profile.username)

            LegalLinks()
        }
        .task { await loadInviteListCount() }
        .sheet(isPresented: $editingProfile) { EditProfileSheet(profile: profile) }
    }

    /// The app's language in its own words: "English", "中文".
    private var languageName: String {
        let locale = Locale(identifier: app.language.localeIdentifier)
        return locale.localizedString(forLanguageCode: app.language.rawValue) ?? app.language.rawValue
    }

    /// Runs on every visit, so the count follows changes made on the Invite lists screen.
    private func loadInviteListCount() async {
        if let groups = try? await app.service.groups() { inviteListCount = groups.count }
    }

    private func toggleAnonymousDefault(_ value: Bool) async {
        app.updateMe { $0.anonymousBallotByDefault = value }
        do {
            try await app.service.updateProfile(anonymousBallotByDefault: value)
            savedAnonymousDefault = value
        } catch {
            app.updateMe { $0.anonymousBallotByDefault = savedAnonymousDefault }
            app.showToast(app.t.message(for: error, fallback: "account.saveFailed"), isError: true)
        }
    }
}

/// Which kinds the feed and the unread count include; each switch changes at once and goes back if the save fails.
private struct NotificationSwitches: View {
    @Environment(AppModel.self) private var app
    private typealias Key = WritableKeyPath<NotificationPreferences, Bool>

    /// The switches in the web's order (`NOTIFICATION_SWITCHES`): each row's title and body.
    private static let switches: [(key: Key, title: String, body: String)] = [
        (\.resultsIn, "settings.notifyResultsIn", "settings.notifyResultsInBody"),
        (\.invitations, "settings.notifyInvitations", "settings.notifyInvitationsBody"),
        (\.comments, "settings.notifyComments", "settings.notifyCommentsBody"),
        (\.closingSoon, "settings.notifyClosingSoon", "settings.notifyClosingSoonBody"),
    ]

    @State private var preferences: NotificationPreferences?
    @State private var failed = false
    /// One save per switch at a time, so the server can't apply an older toggle after a newer one.
    @State private var saving: Set<Key> = []

    var body: some View {
        Group {
            if let preferences {
                VStack(spacing: 0) {
                    ForEach(Array(Self.switches.enumerated()), id: \.offset) { index, item in
                        if index > 0 { RowDivider() }
                        Toggle(isOn: Binding(
                            get: { preferences[keyPath: item.key] },
                            set: { value in Task { await set(item.key, value) } }
                        )) {
                            RowText(title: app.t(item.title), detail: app.t(item.body))
                        }
                        .tint(Tokens.primary)
                        .disabled(saving.contains(item.key))
                        .settingsRow()
                    }
                }
                .card(padding: nil)
            } else if failed {
                HStack(spacing: 12) {
                    Text(app.t("settings.notificationsFailed")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LoadingButton(style: .vm(.outline, size: .sm), action: load) { Text(app.t("common.tryAgain")) }
                }
                .settingsRow()
                .card(padding: nil)
            } else {
                Skeleton(height: 280, radius: Radius.card)
            }
        }
        .task(id: app.sessionGeneration) { await load() }
    }

    private func load() async {
        failed = false
        do {
            preferences = try await app.service.notificationPreferences()
        } catch {
            failed = preferences == nil
        }
    }

    private func set(_ key: Key, _ value: Bool) async {
        preferences?[keyPath: key] = value
        saving.insert(key)
        defer { saving.remove(key) }
        do {
            let saved = try await app.service.updateNotificationPreferences(
                resultsIn: key == \.resultsIn ? value : nil, invitations: key == \.invitations ? value : nil,
                comments: key == \.comments ? value : nil, closingSoon: key == \.closingSoon ? value : nil
            )
            // Only this switch: another one may still be saving
            preferences?[keyPath: key] = saved[keyPath: key]
            // A kind switched off leaves the unread count
            await app.refreshUnread()
        } catch {
            preferences?[keyPath: key] = !value
            app.showToast(app.t.message(for: error, fallback: "account.saveFailed"), isError: true)
        }
    }
}

/// People the user blocked, each with Unblock: a row inside the Privacy card (the web's
/// `BlockedUsersPanel`, `embedded`): the title with a mono count, then soft tiles.
private struct BlockedPeople: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(app.t("blocks.title")).font(.vm(15, .medium)).foregroundStyle(Tokens.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !app.blocked.isEmpty {
                    Text(app.t.number(app.blocked.count)).font(.vmMono(14)).foregroundStyle(Tokens.mutedForeground)
                }
            }
            if app.blocked.isEmpty {
                Text(app.t("blocks.empty")).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
            }
            ForEach(app.blocked, id: \.self) { username in
                HStack(spacing: 10) {
                    AvatarView(username: username, avatarUrl: nil, size: 28)
                    Text("@\(username)").font(.vmMono(14)).foregroundStyle(Tokens.foreground).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(app.t("blocks.unblock")) {
                        app.unblock(username)
                        app.showToast(app.t("blocks.unblocked", ["username": username]))
                    }
                    .buttonStyle(.vm(.outline, size: .sm))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Tokens.surfaceSoft, in: RoundedRectangle(cornerRadius: Radius.xl))
                .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
            }
        }
    }
}

/// People the user follows, each with Unfollow (the web's `FollowedUsersPanel`).
private struct FollowedPeople: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.t("follows.title")).font(.vm(15, .medium)).foregroundStyle(Tokens.foreground)
                Text(app.t("follows.intro")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            if app.following.isEmpty {
                EmptyState { Text(app.t("follows.empty")) }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.following.enumerated()), id: \.element.id) { index, user in
                        if index > 0 { RowDivider() }
                        row(user)
                    }
                }
                .card(padding: nil)
            }
        }
    }

    private func row(_ user: UserSummary) -> some View {
        HStack(spacing: 12) {
            Button { app.push(.profile(user.username)) } label: {
                HStack(spacing: 12) {
                    AvatarView(username: user.username, avatarUrl: user.avatarUrl, size: 40)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(user.displayName ?? user.username).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
                        Text("@\(user.username)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(app.t("ios.openProfile"))
            Button(app.t("follows.unfollow")) {
                app.unfollow(user.id)
                app.showToast(app.t("follows.unfollowed", ["username": user.username]))
            }
            .buttonStyle(.vm(.outline, size: .sm))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Passkeys on the account (the web's `PasskeysPanel`): the list, each removable after
/// confirmation, and Add passkey for this device.
private struct PasskeysSection: View {
    @Environment(AppModel.self) private var app
    @State private var model: PasskeysModel
    @State private var confirming: Passkey?

    init(service: VomattService) {
        _model = State(initialValue: PasskeysModel(service: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RowText(title: app.t("passkey.title"), detail: app.t("passkey.body"))
                LoadingButton(style: .vm(.outline, size: .sm), action: add) { Text(app.t("passkey.add")) }
            }
            if model.loadFailed {
                HStack(spacing: 12) {
                    Text(app.t("passkey.loadFailed")).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LoadingButton(style: .vm(.outline, size: .sm), action: { await model.load() }) { Text(app.t("common.tryAgain")) }
                }
            } else if let passkeys = model.passkeys {
                if passkeys.isEmpty {
                    Text(app.t("passkey.empty")).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
                }
                ForEach(passkeys) { passkey in row(passkey) }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task { await model.load() }
        .alert(
            app.t("passkey.deleteConfirmTitle"),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { passkey in
            Button(app.t("common.cancel"), role: .cancel) {}
            Button(app.t("passkey.delete"), role: .destructive) { Task { await delete(passkey) } }
        } message: { passkey in
            Text(app.t("passkey.deleteConfirmBody", ["name": name(passkey)]))
        }
    }

    private func row(_ passkey: Passkey) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(passkey)).font(.vm(14, .medium)).lineLimit(1)
                Text(dates(passkey)).font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(app.t("passkey.delete")) { confirming = passkey }
                .buttonStyle(.vm(.outline, size: .sm))
                .accessibilityLabel(app.t("passkey.deleteLabel", ["name": name(passkey)]))
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { RowDivider() }
    }

    private func name(_ passkey: Passkey) -> String { passkey.name ?? app.t("passkey.unnamed") }

    private func dates(_ passkey: Passkey) -> String {
        let created = app.t("passkey.created", ["date": app.dates.pollDate(passkey.createdAt)])
        let used = passkey.lastUsedAt.map { app.t("passkey.lastUsed", ["date": app.dates.pollDate($0)]) } ?? app.t("passkey.neverUsed")
        return "\(created) · \(used)"
    }

    private func add() async {
        if await model.add(authenticate: PasskeyAuthenticator.register) {
            app.showToast(app.t("passkey.added"))
        } else if let failure = model.failure {
            showError(failure)
        }
    }

    private func delete(_ passkey: Passkey) async {
        if await model.delete(passkey) {
            app.showToast(app.t("passkey.deleted"))
        } else if let failure = model.failure {
            showError(failure)
        }
    }

    private func showError(_ failure: PasskeyFailure) {
        app.showToast(failure.error.map { app.t.message(for: $0, fallback: failure.key) } ?? app.t(failure.key), isError: true)
    }
}

/// Writes the export to a temporary file, then offers it through the share sheet.
private struct ExportDataRow: View {
    @Environment(AppModel.self) private var app
    @State private var file: URL?

    var body: some View {
        HStack(spacing: 12) {
            RowText(title: app.t("account.exportTitle"), detail: app.t("account.exportBody"))
            if let file {
                ShareLink(item: file) { Text(app.t("poll.share")) }.buttonStyle(.vm(.outline, size: .sm))
            } else {
                LoadingButton(style: .vm(.outline, size: .sm), action: export) { Text(app.t("account.exportCta")) }
            }
        }
        .settingsRow()
        .onDisappear(perform: discard)
    }

    private func export() async {
        do {
            let data = try await app.service.exportMyData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("vomatt-data.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            file = url
        } catch {
            let limited = (error as? APIError)?.isRateLimited == true
            app.showToast(app.t.message(for: error, fallback: limited ? "ios.exportLimited" : "account.exportFailed"), isError: true)
        }
    }

    /// The export holds everything about the account, so it doesn't outlive the screen.
    private func discard() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
        self.file = nil
    }
}

/// Opens the feedback sheet (iOS only; the web has no feedback form).
private struct FeedbackRow: View {
    @Environment(AppModel.self) private var app
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 12) {
            RowText(title: app.t("ios.feedbackTitle"), detail: app.t("ios.feedbackBody"))
            Button(app.t("ios.feedbackCta")) { isPresented = true }.buttonStyle(.vm(.outline, size: .sm))
        }
        .settingsRow()
        .sheet(isPresented: $isPresented) { FeedbackSheet() }
    }
}

/// A free-text message to the team (max 2000 characters).
private struct FeedbackSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    private static let maxLength = 2000
    private var content: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    VMTextEditor(placeholder: app.t("ios.feedbackPlaceholder"), text: $text, minHeight: 160)
                    if let error { Text(error).font(.vm(14)).foregroundStyle(Tokens.destructive) }
                }
                .padding(Metrics.gutter)
            }
            .canvas()
            .navigationTitle(app.t("ios.feedbackTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(app.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    LoadingButton(style: .vm(.link), action: send) { Text(app.t("ios.feedbackSend")).fontWeight(.semibold) }
                        .disabled(content.isEmpty || content.utf16.count > Self.maxLength)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() async {
        error = nil
        do {
            try await app.service.sendFeedback(content)
            app.showToast(app.t("ios.feedbackSent"))
            dismiss()
        } catch {
            let limited = (error as? APIError)?.isRateLimited == true
            self.error = app.t.message(for: error, fallback: limited ? "ios.feedbackLimited" : "ios.feedbackFailed")
        }
    }
}

/// Typing the username confirms a permanent delete (App Store guideline 5.1.1(v)).
private struct DeleteAccountSection: View {
    @Environment(AppModel.self) private var app
    let username: String
    @State private var isPresented = false
    @State private var confirmation = ""

    /// Deletion refusals with their own copy; anything else goes through `message(for:)`.
    private static let errorKeys = ["admin.last_admin": "account.deleteLastAdmin"]

    private var matches: Bool {
        confirmation.trimmingCharacters(in: .whitespaces).lowercased() == username.lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isPresented = true } label: {
                Text(app.t("account.deleteCtaEllipsis")).font(.vm(15, .medium)).foregroundStyle(Tokens.destructive)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .card(padding: nil, border: Tokens.destructive.opacity(0.3))
            Text(app.t("account.deleteBody")).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
                .padding(.horizontal, 16)
        }
        .alert(app.t("account.deleteConfirmTitle"), isPresented: $isPresented) {
            TextField(username, text: $confirmation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(app.t("account.deleteConfirmLabel"))
            Button(app.t("common.cancel"), role: .cancel) { confirmation = "" }
            Button(app.t("account.deleteCta"), role: .destructive) { Task { await delete() } }
                .disabled(!matches)
        } message: {
            Text(app.t("account.deleteConfirmBody", ["username": username]))
        }
    }

    private func delete() async {
        guard matches else { return }
        confirmation = ""
        do {
            try await app.service.deleteMyAccount()
            app.selectedTab = .home
        } catch {
            let key = (error as? APIError)?.errorCode.flatMap { Self.errorKeys[$0] }
            app.showToast(key.map { app.t($0) } ?? app.t.message(for: error, fallback: "account.deleteFailed"), isError: true)
        }
    }
}

/// Terms, Privacy, Cookies and Contact, then the version (the web's `LegalLinks`); shown signed in or out.
struct LegalLinks: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        let site = app.config.siteURL
        VStack(spacing: 8) {
            HStack(spacing: 18) {
                link(app.t("settings.terms"), site.appending(path: "terms-of-service"))
                link(app.t("settings.privacyPolicy"), site.appending(path: "privacy-policy"))
                link(app.t("settings.cookies"), site.appending(path: "cookies-policy"))
                if !app.config.supportEmail.isEmpty, let mail = URL(string: "mailto:\(app.config.supportEmail)") {
                    link(app.t("ios.contact"), mail)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(app.t("settings.legal"))
            Text(version).font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
        }
        .frame(maxWidth: .infinity)
    }

    private func link(_ title: String, _ url: URL) -> some View {
        Button(title) { openURL(url) }
            .font(.vm(13))
            .foregroundStyle(Tokens.mutedForeground)
            .buttonStyle(.plain)
            .frame(minHeight: Metrics.minTarget)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "v\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
}

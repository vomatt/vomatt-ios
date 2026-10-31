import SwiftUI
import VomattCore

/// Settings, pushed from the gear on the profile (the web's `/settings`).
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

/// Which kinds of notification show in the feed and the unread count.
private struct NotificationPreferencesSection: View {
    @Environment(AppModel.self) private var app
    private enum Switch: CaseIterable { case resultsIn, invitations, comments, mentions, likes, closingSoon }

    @State private var preferences: NotificationPreferences?
    @State private var failed = false
    @State private var inFlight = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SectionTitle(text: app.t("ios.notifPrefsTitle"))
                Text(app.t("ios.notifPrefsBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            if let preferences {
                VStack(spacing: 0) {
                    ForEach(Switch.allCases, id: \.self) { item in
                        Toggle(label(item), isOn: Binding(
                            get: { value(item, preferences) },
                            set: { newValue in Task { await set(item, newValue) } }
                        ))
                        .font(.vm(14))
                        .tint(Tokens.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) {
                            if item != Switch.allCases.last { Rectangle().fill(Tokens.border).frame(height: 1) }
                        }
                    }
                }
                .card(padding: nil)
            } else if failed {
                LoadFailed(message: app.t("ios.notifPrefFailed")) { await load() }
            } else {
                Skeleton(height: 312, radius: Radius.xl)
            }
        }
        .task(id: app.sessionGeneration) { await load() }
    }

    private func label(_ item: Switch) -> String {
        switch item {
        case .resultsIn: app.t("ios.notifPrefResults")
        case .invitations: app.t("ios.notifPrefInvitations")
        case .comments: app.t("ios.notifPrefComments")
        case .mentions: app.t("ios.notifPrefMentions")
        case .likes: app.t("ios.notifPrefLikes")
        case .closingSoon: app.t("ios.notifPrefClosingSoon")
        }
    }

    private func value(_ item: Switch, _ preferences: NotificationPreferences) -> Bool {
        switch item {
        case .resultsIn: preferences.resultsIn
        case .invitations: preferences.invitations
        case .comments: preferences.comments
        case .mentions: preferences.mentions
        case .likes: preferences.likes
        case .closingSoon: preferences.closingSoon
        }
    }

    private func load() async {
        failed = false
        do {
            preferences = try await app.service.notificationPreferences()
        } catch {
            failed = preferences == nil
        }
    }

    /// Shows the new value at once; the API's answer, or the old value after a failure, replaces it.
    private func set(_ item: Switch, _ newValue: Bool) async {
        guard let previous = preferences else { return }
        let before = value(item, previous)
        setValue(item, newValue)
        inFlight += 1
        defer { inFlight -= 1 }
        do {
            let saved = try await app.service.updateNotificationPreferences(
                resultsIn: item == .resultsIn ? newValue : nil, invitations: item == .invitations ? newValue : nil,
                comments: item == .comments ? newValue : nil, mentions: item == .mentions ? newValue : nil, likes: item == .likes ? newValue : nil,
                closingSoon: item == .closingSoon ? newValue : nil
            )
            // Another toggle still in flight: its answer carries the final state.
            if inFlight == 1 { preferences = saved }
            await app.refreshUnread()
        } catch {
            setValue(item, before)
            app.showToast(app.t.message(for: error, fallback: "ios.notifPrefFailed"), isError: true)
        }
    }

    private func setValue(_ item: Switch, _ newValue: Bool) {
        switch item {
        case .resultsIn: preferences?.resultsIn = newValue
        case .invitations: preferences?.invitations = newValue
        case .comments: preferences?.comments = newValue
        case .mentions: preferences?.mentions = newValue
        case .likes: preferences?.likes = newValue
        case .closingSoon: preferences?.closingSoon = newValue
        }
    }
}

/// Visibility switches, sign out, delete account.
private struct AccountSettings: View {
    @Environment(AppModel.self) private var app
    let profile: MyProfile
    @State private var confirmingSignOut = false
    /// The last Ballot default the server confirmed; quick toggles can answer out of order.
    @State private var savedAnonymousDefault: Bool

    init(profile: MyProfile) {
        self.profile = profile
        _savedAnonymousDefault = State(initialValue: profile.anonymousBallotByDefault)
    }

    /// Fields whose labels are iOS-only strings.
    private let extraFields: Set = ["firstName", "lastName"]
    /// Profile fields other people can see, in the order shown.
    private let fields = ["displayName", "firstName", "lastName", "bio", "location", "points", "membershipLevel"]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle(text: app.t("account.privacyTitle"))
                    Text(app.t("account.privacyBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                }
                VStack(spacing: 0) {
                    ForEach(fields, id: \.self) { field in
                        Toggle(app.t(extraFields.contains(field) ? "ios.field.\(field)" : "account.field.\(field)"), isOn: Binding(
                            get: { profile.visibilitySettings[field] == true },
                            set: { value in Task { await toggle(field, value) } }
                        ))
                        .font(.vm(14))
                        .tint(Tokens.primary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .overlay(alignment: .bottom) {
                            if field != fields.last { Rectangle().fill(Tokens.border).frame(height: 1) }
                        }
                    }
                }
                .card(padding: nil)
            }

            Toggle(isOn: Binding(
                get: { profile.anonymousBallotByDefault },
                set: { value in Task { await toggleAnonymousDefault(value) } }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.t("account.anonymousDefault")).font(.vm(15, .medium))
                    Text(app.t("account.anonymousDefaultBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                }
            }
            .tint(Tokens.primary)
            .card()

            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: app.t("account.tabGroups"))
                GroupsPanel()
            }

            PasskeysSection(service: app.service)

            DevicesSection(service: app.service)

            NotificationPreferencesSection()

            if !app.following.isEmpty { followingSection }
            if !app.blocked.isEmpty { blockedSection }

            AppSettingsSection()

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.t("account.signOutTitle")).font(.vm(15, .medium))
                    Text(profile.email ?? profile.username).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button(app.t("account.signOut")) { confirmingSignOut = true }.buttonStyle(.vm(.outline))
            }
            .card()
            .confirmationDialog(app.t("account.signOut"), isPresented: $confirmingSignOut) {
                Button(app.t("account.signOut"), role: .destructive) { Task { await app.signOut() } }
            }

            FeedbackSection()

            ExportDataSection()

            DeleteAccountSection(username: profile.username)
        }
    }

    private var followingSection: some View {
        peopleSection(title: app.t("profile.following"), actionTitle: app.t("ios.unfollowShort"), people: app.following.map { user in
            Person(id: user.id, username: user.username, avatarUrl: user.avatarUrl, link: true, action: { app.unfollow(user.id) })
        })
    }

    private var blockedSection: some View {
        peopleSection(title: app.t("ios.blockedTitle"), actionTitle: app.t("ios.unblock"), people: app.blocked.map { username in
            Person(id: username, username: username, avatarUrl: nil, link: false, action: { app.unblock(username) })
        })
    }

    private struct Person: Identifiable {
        let id: String
        let username: String
        let avatarUrl: String?
        let link: Bool
        let action: () -> Void
    }

    /// A card of people, each with one outline button (unfollow, unblock).
    private func peopleSection(title: String, actionTitle: String, people: [Person]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: title)
            VStack(spacing: 0) {
                ForEach(people) { person in
                    HStack {
                        UserChip(username: person.username, avatarUrl: person.avatarUrl, avatarSize: 28, link: person.link).font(.vm(15))
                        Spacer()
                        Button(actionTitle, action: person.action).buttonStyle(.vm(.outline, size: .sm))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .overlay(alignment: .bottom) {
                        if person.id != people.last?.id { Rectangle().fill(Tokens.border).frame(height: 1) }
                    }
                }
            }
            .card(padding: nil)
        }
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

    private func toggle(_ field: String, _ value: Bool) async {
        let previous = profile.visibilitySettings
        app.updateMe { $0.visibilitySettings[field] = value }
        do {
            let settings = try await app.service.updateVisibility([field: value])
            app.updateMe { $0.visibilitySettings = settings }
        } catch {
            app.updateMe { $0.visibilitySettings = previous }
            app.showToast(app.t.message(for: error, fallback: "account.saveFailed"), isError: true)
        }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.t("passkey.title")).font(.vm(15, .medium))
                    Text(app.t("passkey.body")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LoadingButton(style: .vm(.outline), action: add) { Text(app.t("passkey.add")) }
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
        .card()
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
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
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

/// Devices signed in to the account: each other one can be signed out after confirmation, or all
/// at once. This device signs out with Sign out below.
private struct DevicesSection: View {
    @Environment(AppModel.self) private var app
    @State private var model: DevicesModel
    @State private var confirming: DeviceSession?
    @State private var confirmingOthers = false

    init(service: VomattService) {
        _model = State(initialValue: DevicesModel(service: service))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.t("devices.title")).font(.vm(15, .medium))
                Text(app.t("devices.body")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            if model.loadFailed {
                HStack(spacing: 12) {
                    Text(app.t("devices.loadFailed")).font(.vm(13)).foregroundStyle(Tokens.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LoadingButton(style: .vm(.outline, size: .sm), action: { await model.load() }) { Text(app.t("common.tryAgain")) }
                }
            } else if let devices = model.devices {
                ForEach(devices) { device in row(device) }
                if model.hasOthers {
                    Button(app.t("devices.signOutOthers")) { confirmingOthers = true }
                        .buttonStyle(.vm(.outline, fullWidth: true))
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .card()
        .task { await model.load() }
        .alert(
            app.t("devices.signOutTitle"),
            isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
            presenting: confirming
        ) { device in
            Button(app.t("common.cancel"), role: .cancel) {}
            Button(app.t("devices.signOut"), role: .destructive) { Task { await signOut(device) } }
        } message: { device in
            Text(app.t("devices.signOutBody", ["name": name(device)]))
        }
        .alert(app.t("devices.signOutOthersTitle"), isPresented: $confirmingOthers) {
            Button(app.t("common.cancel"), role: .cancel) {}
            Button(app.t("devices.signOut"), role: .destructive) { Task { await signOutOthers() } }
        } message: {
            Text(app.t("devices.signOutOthersBody"))
        }
    }

    private func row(_ device: DeviceSession) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name(device)).font(.vm(14, .medium)).lineLimit(1)
                if device.isCurrent || device.isAdminScope {
                    HStack(spacing: 6) {
                        if device.isCurrent { Chip(text: app.t("devices.current"), bordered: true) }
                        if device.isAdminScope { Chip(text: app.t("devices.admin")) }
                    }
                }
                if let dates = dates(device) {
                    Text(dates).font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !device.isCurrent {
                Button(app.t("devices.signOut")) { confirming = device }
                    .buttonStyle(.vm(.outline, size: .sm))
                    .accessibilityLabel(app.t("devices.signOutLabel", ["name": name(device)]))
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Rectangle().fill(Tokens.border).frame(height: 1) }
    }

    private func name(_ device: DeviceSession) -> String { device.deviceName ?? app.t("devices.unknown") }

    private func dates(_ device: DeviceSession) -> String? {
        let parts = [
            device.createdAt.map { app.t("devices.signedInOn", ["date": app.dates.pollDate($0)]) },
            device.lastSeenAt.map { app.t("devices.lastActive", ["date": app.dates.pollDate($0)]) },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func signOut(_ device: DeviceSession) async {
        if await model.signOut(device) {
            app.showToast(app.t("devices.signedOut"))
        } else {
            showError()
        }
    }

    private func signOutOthers() async {
        if await model.signOutOthers() {
            app.showToast(app.t("devices.othersSignedOut"))
        } else {
            showError()
        }
    }

    private func showError() {
        guard let error = model.failure else { return }
        app.showToast(app.t.message(for: error, fallback: "devices.signOutFailed"), isError: true)
    }
}

/// Legal links and the version; shown signed in or out.
struct AppSettingsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        let mail = app.config.supportEmail.isEmpty ? nil : URL(string: "mailto:\(app.config.supportEmail)")
        VStack(spacing: 0) {
            link(app.t("ios.terms"), url: app.config.siteURL.appending(path: "terms-of-service"))
            link(app.t("ios.privacy"), url: app.config.siteURL.appending(path: "privacy-policy"), last: mail == nil)
            if let mail {
                link(app.t("ios.contact"), url: mail, last: true)
            }
        }
        .card(padding: nil)
        .overlay(alignment: .bottomTrailing) {
            Text(version).font(.vmMono(11)).foregroundStyle(Tokens.mutedForeground).offset(y: 20)
        }
        .padding(.bottom, 12)
    }

    private func link(_ title: String, url: URL, last: Bool = false) -> some View {
        Button { openURL(url) } label: {
            HStack {
                Text(title).font(.vm(14)).foregroundStyle(Tokens.foreground)
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 12)).foregroundStyle(Tokens.mutedForeground)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(Tokens.border).frame(height: 1) } }
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "v\(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))"
    }
}

/// Opens the feedback sheet.
private struct FeedbackSection: View {
    @Environment(AppModel.self) private var app
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.t("ios.feedbackTitle")).font(.vm(15, .medium))
                Text(app.t("ios.feedbackBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(app.t("ios.feedbackCta")) { isPresented = true }.buttonStyle(.vm(.outline))
        }
        .card()
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

/// Writes the export to a temporary file, then offers it through the share sheet.
private struct ExportDataSection: View {
    @Environment(AppModel.self) private var app
    @State private var file: URL?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.t("ios.exportTitle")).font(.vm(15, .medium))
                Text(app.t("ios.exportBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let file {
                ShareLink(item: file) { Text(app.t("poll.share")) }.buttonStyle(.vm(.outline))
            } else {
                LoadingButton(style: .vm(.outline), action: export) { Text(app.t("ios.exportCta")) }
            }
        }
        .card()
        .onDisappear(perform: discard)
    }

    private func export() async {
        do {
            let data = try await app.service.exportMyData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("vomatt-export.json")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            file = url
        } catch {
            let limited = (error as? APIError)?.isRateLimited == true
            app.showToast(app.t.message(for: error, fallback: limited ? "ios.exportLimited" : "ios.exportFailed"), isError: true)
        }
    }

    /// The export holds everything about the account, so it doesn't outlive the screen.
    private func discard() {
        guard let file else { return }
        try? FileManager.default.removeItem(at: file)
        self.file = nil
    }
}

/// Typing the username confirms a permanent delete (App Store guideline 5.1.1(v)).
private struct DeleteAccountSection: View {
    @Environment(AppModel.self) private var app
    let username: String
    @State private var isPresented = false
    @State private var confirmation = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(app.t("account.deleteTitle")).font(.vm(15, .medium)).foregroundStyle(Tokens.destructive)
                Text(app.t("account.deleteBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            Button(app.t("account.deleteCta")) { isPresented = true }.buttonStyle(.vm(.destructive))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(border: Tokens.destructive.opacity(0.3))
        .alert(app.t("account.deleteConfirmTitle"), isPresented: $isPresented) {
            TextField(username, text: $confirmation)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(app.t("common.cancel"), role: .cancel) { confirmation = "" }
            Button(app.t("account.deleteCta"), role: .destructive) { Task { await delete() } }
                .disabled(confirmation != username)
        } message: {
            Text(app.t("account.deleteConfirmBody", ["username": username]))
        }
    }

    private func delete() async {
        guard confirmation == username else { return }
        confirmation = ""
        do {
            try await app.service.deleteMyAccount()
            app.selectedTab = .home
        } catch {
            app.showToast(app.t.message(for: error, fallback: "common.error"), isError: true)
        }
    }
}

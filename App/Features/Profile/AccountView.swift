import SwiftUI
import VomattCore

/// The signed-in user's own page: header, numbers and the Activity / Polls / Groups / Settings tabs.
struct AccountView: View {
    @Environment(AppModel.self) private var app
    let profile: MyProfile

    enum Tab: Hashable { case activity, polls, groups, settings }
    @State private var tab = Tab.activity
    @State private var polls: [Poll]?
    @State private var showEdit = false
    @State private var showAvatar = false

    private var myPolls: [Poll] { app.visible(polls ?? []).filter { $0.creatorId == profile.id } }
    private var history: [BallotRecord] { AccountInsights.history(app.visible(polls ?? [])) }
    private var insights: Insights { AccountInsights.compute(myPolls: myPolls, history: history) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // The header leaves out fields hidden from visitors, as they see it
                ProfileHeader(profile: profile.asPublicProfile, onAvatarTap: { showAvatar = true }) {
                    Button(app.t("profile.editProfile")) { showEdit = true }.buttonStyle(.vm(.outline, size: .sm))
                }
                StatsGrid(stats: [
                    (app.t("account.votesCast"), app.t.number(profile.totalVotes)),
                    (app.t("account.pollsCreated"), app.t.number(profile.totalPolls)),
                    (app.t("account.peopleReached"), app.t.number(insights.peopleReached)),
                    (app.t("account.majorityRate"), insights.majorityRate.map { "\($0)%" } ?? app.t("account.majorityNone")),
                ])
                .accessibilityLabel(app.t("account.stats"))

                VStack(alignment: .leading, spacing: 16) {
                    LineTabs(items: [
                        (Tab.activity, app.t("account.tabActivity") + (insights.awaitingResults > 0 ? " · \(insights.awaitingResults)" : "")),
                        (Tab.polls, app.t("account.tabPolls")),
                        (Tab.groups, app.t("account.tabGroups")),
                        (Tab.settings, app.t("account.tabSettings")),
                    ], selection: $tab)
                    switch tab {
                    case .activity: activity
                    case .polls: pollsList
                    case .groups: GroupsPanel()
                    case .settings: AccountSettings(profile: profile)
                    }
                }
            }
            .pageColumn(768)
            .padding(.vertical, 24)
        }
        .refreshable { await load() }
        .canvas()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.sessionGeneration) { await load() }
        .sheet(isPresented: $showEdit) { EditProfileSheet(profile: profile) }
        .sheet(isPresented: $showAvatar) { AvatarPickerSheet(username: profile.username, avatarUrl: profile.avatarUrl) }
    }

    @ViewBuilder private var activity: some View {
        if polls == nil {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 32)
        } else if history.isEmpty {
            EmptyState {
                Text(app.t("account.noVotes"))
                Button(app.t("account.findPolls")) { app.selectedTab = .home }.buttonStyle(.vm)
            }
        } else {
            LazyVStack(spacing: 8) {
                ForEach(history) { record in
                    PollRow(poll: record.poll) {
                        Text(app.t("account.youChose")) + Text(" ") + Text(record.choice).foregroundStyle(Tokens.foreground).fontWeight(.medium)
                    } aside: {
                        Chip(text: app.t("account.outcome.\(record.outcome.rawValue)"), tint: tint(record.outcome))
                    }
                }
            }
        }
    }

    @ViewBuilder private var pollsList: some View {
        if myPolls.isEmpty {
            EmptyState { Text(app.t("account.noPolls")) }
        } else {
            LazyVStack(spacing: 8) {
                ForEach(myPolls) { poll in
                    PollRow(poll: poll) {
                        Text(app.t("poll.voted", ["count": app.t.number(poll.turnout ?? 0)]))
                    } aside: {
                        StatusChip(poll: poll)
                    }
                }
            }
        }
    }

    private func tint(_ outcome: BallotOutcome) -> Color {
        switch outcome {
        case .pending: Tokens.statusScheduled
        case .won: Tokens.statusOpen
        case .tied: Tokens.statusClosing
        case .lost, .unknown: Tokens.secondary
        }
    }

    /// Every Poll the user created or holds a Ballot in, so insights cover them all.
    private func load() async {
        async let open = try? app.service.allMyPolls(status: .open)
        async let ended = try? app.service.allMyPolls(status: .ended)
        polls = (await open ?? []) + (await ended ?? [])
        await app.refreshAccount()
    }
}

/// Visibility switches, language, sign out, delete account.
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

    /// Profile fields other people can see, in the order shown.
    private let fields = ["displayName", "bio", "location", "points", "membershipLevel"]

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionTitle(text: app.t("account.privacyTitle"))
                    Text(app.t("account.privacyBody")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                }
                VStack(spacing: 0) {
                    ForEach(fields, id: \.self) { field in
                        Toggle(app.t("account.field.\(field)"), isOn: Binding(
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

            DeleteAccountSection(username: profile.username)
        }
    }

    private var blockedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: app.t("ios.blockedTitle"))
            VStack(spacing: 0) {
                ForEach(app.blocked, id: \.self) { username in
                    HStack {
                        UserChip(username: username, avatarUrl: nil, avatarSize: 28, link: false).font(.vm(15))
                        Spacer()
                        Button(app.t("ios.unblock")) { app.unblock(username) }.buttonStyle(.vm(.outline, size: .sm))
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 56)
                    .overlay(alignment: .bottom) {
                        if username != app.blocked.last { Rectangle().fill(Tokens.border).frame(height: 1) }
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

/// Language, legal links and the version; shown signed in or out.
struct AppSettingsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            Picker(selection: $app.language) {
                ForEach(Language.allCases, id: \.self) { Text($0.displayName).tag($0) }
            } label: {
                Text(app.t("ios.language")).font(.vm(14)).foregroundStyle(Tokens.foreground)
            }
            .tint(Tokens.mutedForeground)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .overlay(alignment: .bottom) { Rectangle().fill(Tokens.border).frame(height: 1) }

            link(app.t("ios.terms"), url: app.config.siteURL.appending(path: "terms-of-service"))
            link(app.t("ios.privacy"), url: app.config.siteURL.appending(path: "privacy-policy"))
            if !app.config.supportEmail.isEmpty, let mail = URL(string: "mailto:\(app.config.supportEmail)") {
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

/// Username, display name and bio (the web's `EditProfileDialog`).
struct EditProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let profile: MyProfile
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var error: String?

    private var usernameError: String? {
        username == profile.username || Username.isValid(username) ? nil : app.t("account.usernameInvalid")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VMTextField(label: app.t("account.usernameLabel"), placeholder: profile.username, text: $username,
                                hint: app.t("account.usernameHint", ["path": app.config.profileURL(username).absoluteString]),
                                error: usernameError, contentType: .username, autocapitalization: .never)
                    VMTextField(label: app.t("profile.displayName"), placeholder: "", text: $displayName, contentType: .nickname)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.t("profile.bio")).font(.vm(14, .medium))
                        VMTextEditor(placeholder: "", text: $bio, minHeight: 96)
                    }
                    if let error { Text(error).font(.vm(14)).foregroundStyle(Tokens.destructive) }
                }
                .padding(Metrics.gutter)
            }
            .canvas()
            .navigationTitle(app.t("profile.editProfile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(app.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    LoadingButton(style: .vm(.link), action: save) { Text(app.t("common.save")).fontWeight(.semibold) }
                        .disabled(usernameError != nil)
                }
            }
        }
        .onAppear {
            username = profile.username
            displayName = profile.displayName ?? ""
            bio = profile.bio ?? ""
        }
    }

    private func save() async {
        error = nil
        do {
            let newUsername = username == profile.username ? nil : username
            try await app.service.updateProfile(username: newUsername, displayName: displayName, bio: bio)
            app.updateMe {
                $0.username = username
                $0.displayName = displayName.isEmpty ? nil : displayName
                $0.bio = bio.isEmpty ? nil : bio
            }
            dismiss()
        } catch {
            // The API's message is localized and explains, e.g., a taken username
            self.error = app.t.message(for: error, fallback: "account.saveFailed")
        }
    }
}

/// The bot cast, in four families (the web's `AvatarDialog`).
struct AvatarPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let username: String
    let avatarUrl: String?
    @State private var selected = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 16) {
                        AvatarView(username: username, avatarUrl: Avatars.avatarUrl(for: selected), size: 72)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.t("avatar.bots.\(selected).name")).font(.vm(17, .medium))
                            Text(app.t("avatar.bots.\(selected).trait")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                        }
                        Spacer()
                        Button(app.t("avatar.surprise")) { selected = Avatars.kinds.randomElement() ?? selected }
                            .buttonStyle(.vm(.outline, size: .sm))
                    }
                    Text(app.t("avatar.body")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    ForEach(Avatars.families, id: \.name) { family in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(app.t("avatar.families.\(family.name)")).font(.vm(13, .medium)).foregroundStyle(Tokens.mutedForeground)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                                ForEach(family.kinds, id: \.self) { kind in
                                    Button { selected = kind } label: {
                                        AvatarView(username: username, avatarUrl: Avatars.avatarUrl(for: kind), size: 48)
                                            .overlay(Circle().strokeBorder(Tokens.foreground, lineWidth: selected == kind ? 2 : 0).padding(-3))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(app.t("avatar.choose", ["name": app.t("avatar.bots.\(kind).name")]))
                                    .accessibilityAddTraits(selected == kind ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                .padding(Metrics.gutter)
            }
            .canvas()
            .navigationTitle(app.t("avatar.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(app.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    LoadingButton(style: .vm(.link), action: save) { Text(app.t("avatar.save")).fontWeight(.semibold) }
                }
            }
        }
        .onAppear { selected = Avatars.resolve(username: username, avatarUrl: avatarUrl) }
    }

    private func save() async {
        do {
            try await app.service.chooseAvatar(kind: selected)
            app.updateMe { $0.avatarUrl = Avatars.avatarUrl(for: selected) }
            app.showToast(app.t("avatar.savedToast"))
            dismiss()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "account.saveFailed"), isError: true)
        }
    }
}

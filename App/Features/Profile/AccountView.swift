import SwiftUI
import VomattCore

/// The signed-in user's own page (the web's `OwnProfileView`): their record, then two lists one at a time.
/// Asked holds their polls and drafts; Voted holds the polls they voted in and what they chose, which only they see.
struct AccountView: View {
    @Environment(AppModel.self) private var app
    let profile: MyProfile

    enum Tab: Hashable { case asked, voted }
    enum AskedFilter: Hashable { case all, drafts, open, ended }
    enum VotedFilter: Hashable { case all, sealed, decided }
    @State private var tab = Tab.asked
    @State private var askedFilter = AskedFilter.all
    @State private var votedFilter = VotedFilter.all
    /// Every Poll in My Polls, asked and voted in; nil until loaded.
    @State private var polls: [Poll]?
    @State private var loadFailed = false
    @State private var drafts: [PollDraft] = []
    @State private var showEdit = false
    @State private var showAvatar = false

    var body: some View {
        let visible = app.visible(polls ?? [])
        let asked = ProfileLists.asked(visible, viewerId: profile.id)
        let voted = ProfileLists.voted(visible, viewerId: profile.id)
        let askedSplit = ProfileLists.splitAsked(asked)
        let votedSplit = ProfileLists.splitVoted(voted)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Every field, with a lock on each one visitors don't see (the web's `hiddenFields`)
                ProfileHeader(profile: profile.asOwnProfile, onAvatarTap: { showAvatar = true }, hiddenFields: profile.hiddenFields) {
                    Button(app.t("profile.editProfile")) { showEdit = true }.buttonStyle(.vm(.outline, size: .sm))
                    Button { app.push(.settings) } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.vm(.outline, size: .icon))
                        .accessibilityLabel(app.t("navigation.settings"))
                }
                FollowCounts(username: profile.username, followers: profile.followersCount, following: profile.followingCount)
                StatsGrid(stats: [
                    .init(label: app.t("profile.recordAsked"), value: app.t.number(profile.totalPolls)),
                    .init(label: app.t("profile.recordVoted"), value: app.t.number(profile.totalVotes)),
                    .init(
                        label: app.t("profile.recordReached"),
                        value: polls == nil ? "–" : app.t.number(asked.reduce(0) { $0 + ($1.turnout ?? 0) }),
                        onlyYou: true
                    ),
                    .init(
                        label: app.t("profile.recordPicksWon"),
                        value: ProfileLists.picksWonRate(voted).map { "\(app.t.number($0))%" } ?? "–",
                        onlyYou: true
                    ),
                ])

                VStack(alignment: .leading, spacing: 12) {
                    LineTabs(items: [(Tab.asked, app.t("profile.tabAsked")), (Tab.voted, app.t("profile.tabVoted"))], selection: $tab) { value in
                        switch value {
                        case .asked:
                            TabCount(count: asked.count)
                            if askedSplit.ended.contains(where: { $0.unread == true }) {
                                UnreadDot(label: app.t("profile.askedUnread"))
                            }
                        case .voted:
                            TabCount(count: voted.count)
                            OnlyYouMarker()
                            let unread = votedSplit.decided.filter { $0.unread == true }.count
                            if unread > 0 { UnreadBadge(count: formatUnreadCount(unread), label: app.t("notifications.unread")) }
                        }
                    }
                    switch tab {
                    case .asked:
                        FilterPills(label: app.t("profile.filterLabel"), selection: $askedFilter, options: [
                            (AskedFilter.all, app.t("profile.filterAll"), nil),
                            (AskedFilter.drafts, app.t("myPolls.tabDrafts"), nil),
                            (AskedFilter.open, app.t("profile.filterOpen"), nil),
                            (AskedFilter.ended, app.t("myPolls.tabEnded"), nil),
                        ])
                        lists { askedList(askedSplit) }
                    case .voted:
                        FilterPills(label: app.t("profile.filterLabel"), selection: $votedFilter, options: [
                            (VotedFilter.all, app.t("profile.filterAll"), nil),
                            (VotedFilter.sealed, app.t("profile.filterSealed"), nil),
                            (VotedFilter.decided, app.t("profile.filterDecided"), nil),
                        ])
                        lists { votedList(votedSplit) }
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
        .onAppear { drafts = app.drafts.list() }
        .onChange(of: app.creator == nil) { _, closed in if closed { drafts = app.drafts.list() } }
        .sheet(isPresented: $showEdit) { EditProfileSheet(profile: profile) }
        .sheet(isPresented: $showAvatar) { AvatarPickerSheet(username: profile.username, avatarUrl: profile.avatarUrl) }
    }

    /// The lists once My Polls is in; a failed load isn't an empty list, so it says so and retries.
    @ViewBuilder private func lists(@ViewBuilder _ content: () -> some View) -> some View {
        if polls != nil {
            LazyVStack(alignment: .leading, spacing: 8, content: content)
        } else if loadFailed {
            LoadFailed(message: app.t("profile.pollsLoadFailed")) { await load() }
        } else {
            VStack(spacing: 8) { ForEach(0..<3, id: \.self) { _ in PollRowSkeleton() } }
        }
    }

    @ViewBuilder private func askedList(_ split: (open: [Poll], ended: [Poll])) -> some View {
        if askedFilter == .drafts {
            if drafts.isEmpty {
                EmptyState { Text(app.t("profile.noDrafts")) }
            } else {
                ForEach(drafts) { draftRow($0) }
            }
        } else {
            let open = askedFilter == .ended ? [] : split.open
            let ended = askedFilter == .open ? [] : split.ended
            if askedFilter == .all, !drafts.isEmpty {
                ProfileSection(label: app.t("myPolls.tabDrafts"), count: drafts.count, note: app.t("profile.onlyYouSeeThese"), onlyYou: true)
                ForEach(drafts) { draftRow($0) }
            }
            if open.isEmpty, ended.isEmpty {
                if askedFilter == .all {
                    EmptyState {
                        Text(app.t("profile.noPollsYet")).font(.vm(16, .medium)).foregroundStyle(Tokens.foreground)
                        Text(app.t("profile.noPollsYetOwn"))
                        Button(app.t("common.createPoll")) { app.openCreator() }.buttonStyle(.vm)
                    }
                } else {
                    EmptyState { Text(app.t("myPolls.empty")) }
                }
            }
            if !open.isEmpty {
                ProfileSection(label: app.t("profile.sectionOpen"), count: open.count)
                ForEach(open) { AskedRow(poll: $0, isOwn: true) }
            }
            if !ended.isEmpty {
                ProfileSection(label: app.t("myPolls.tabEnded"), count: ended.count)
                ForEach(ended) { AskedRow(poll: $0, isOwn: true) }
            }
        }
    }

    @ViewBuilder private func votedList(_ split: (sealed: [Poll], decided: [Poll])) -> some View {
        let sealed = votedFilter == .decided ? [] : split.sealed
        let decided = votedFilter == .sealed ? [] : split.decided
        if sealed.isEmpty, decided.isEmpty {
            EmptyState { Text(app.t(votedFilter == .all ? "profile.noVotesYet" : "myPolls.empty")) }
        }
        if !sealed.isEmpty {
            ProfileSection(label: app.t("profile.sectionSealed"), count: sealed.count, onlyYou: true)
            ForEach(sealed) { sealedRow($0) }
        }
        if !decided.isEmpty {
            ProfileSection(label: app.t("profile.filterDecided"), count: decided.count)
            ForEach(decided) { decidedRow($0) }
        }
    }

    /// Drafts live on this device only, so only their author sees them: a quieter, dashed row.
    private func draftRow(_ draft: PollDraft) -> some View {
        let title = draft.form.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? app.t("myPolls.untitledDraft") : title
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.vm(17, relativeTo: .headline))
                    .foregroundStyle(title.isEmpty ? Tokens.mutedForeground : Tokens.foreground).lineLimit(1)
                Text(draft.meta(t: app.t, dates: app.dates)).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(app.t("myPolls.draftContinue")) { app.openCreator(draft: draft) }.buttonStyle(.vm(.outline, size: .sm))
            Menu {
                Button(app.t("myPolls.actionDelete"), systemImage: "trash", role: .destructive) { drafts = app.drafts.delete(draft.id) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16))
                    .foregroundStyle(Tokens.mutedForeground)
                    .frame(width: Metrics.minTarget, height: Metrics.minTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(app.t("myPolls.draftMore", ["title": name]))
        }
        .draftCard()
    }

    /// A Sealed Ballot: the pick and when the results open.
    private func sealedRow(_ poll: Poll) -> some View {
        PollRow(poll: poll, sealed: true) {
            joined([
                Text(app.t("myPolls.youChose")) + Text(" ") + Text(AccountInsights.choice(of: poll)).fontWeight(.medium),
                poll.endTime.map { Text(app.t("profile.resultsAt", ["date": app.dates.pollMoment($0)])) },
            ].compactMap { $0 })
        }
    }

    /// A decided Ballot: the pick, how it fared, and the unread dot until the results are opened.
    private func decidedRow(_ poll: Poll) -> some View {
        let unread = poll.unread == true
        let outcome = poll.isCancelled ? nil : poll.myOptionId.map { AccountInsights.outcome(of: poll, optionId: $0) }
        return PollRow(poll: poll, unread: unread) {
            joined([
                Text(app.t("myPolls.youChose")) + Text(" ") + strong(AccountInsights.choice(of: poll)),
                Text(poll.isCancelled ? app.t("notifications.cancelled") : votedCount(poll, app.t)),
                unread ? Text(app.t("profile.new")).foregroundStyle(Tokens.alert) : nil,
            ].compactMap { $0 })
        } aside: {
            if let outcome, outcome == .won || outcome == .tied || outcome == .lost { OutcomeChip(outcome: outcome) }
        }
    }


    /// Every Poll the user created or holds a Ballot in, so the record and both lists cover them all.
    private func load() async {
        do {
            async let open = app.service.allMyPolls(status: .open)
            async let ended = app.service.allMyPolls(status: .ended)
            let (openPolls, endedPolls) = try await (open, ended)
            polls = openPolls + endedPolls
            loadFailed = false
        } catch {
            loadFailed = polls == nil
        }
        await app.refreshAccount()
    }
}

/// A poll in an Asked list (the web's `AskedRow`): "1,284 voted · ends Fri 20:00" while open, "**Yes** won · 2,061 voted"
/// once ended. Only the owner gets the unread dot on results they haven't opened.
struct AskedRow: View {
    @Environment(AppModel.self) private var app
    let poll: Poll
    var isOwn = false

    var body: some View {
        let status = poll.status()
        let unread = isOwn && status == .ended && poll.unread == true
        var parts: [Text] = []
        if status == .ended {
            if poll.isCancelled {
                parts = [Text(app.t("notifications.cancelled"))]
            } else {
                parts = [decided(poll), Text(votedCount(poll, app.t))].compactMap { $0 }
            }
        } else {
            let when = PollTiming(startTime: poll.startTime, endTime: poll.endTime, status: status, t: app.t, dates: app.dates).when
            if status != .scheduled { parts.append(Text(votedCount(poll, app.t)).foregroundStyle(Tokens.foreground)) }
            if let when { parts.append(Text(when)) }
        }
        if unread { parts.append(Text(app.t("profile.new")).foregroundStyle(Tokens.alert)) }
        return PollRow(poll: poll, unread: unread) {
            joined(parts)
        } aside: {
            StatusChip(poll: poll, timeElsewhere: true)
        }
    }

    /// "**Yes** won" or "Tie between **A** and **B**"; nil when there is no winner to name.
    private func decided(_ poll: Poll) -> Text? {
        switch ProfileLists.endedSummary(poll) {
        case let .won(winner):
            return Text.rich(app.t("profile.wonBy"), ["option": strong(winner)])
        case let .tie(winners):
            // The locale's list ("A, B and C"), formatted around placeholders so each name stays bold
            let keys = winners.indices.map { "{\($0)}" }
            let list = app.t.list(keys)
            let names = Dictionary(uniqueKeysWithValues: winners.enumerated().map { ("\($0.offset)", strong($0.element)) })
            return Text.rich(app.t("profile.tieBetween"), ["options": Text.rich(list, names)])
        case .none:
            return nil
        }
    }

}

private func votedCount(_ poll: Poll, _ t: Localizer) -> String {
    t("poll.voted", ["count": t.number(poll.turnout ?? 0)])
}

private func strong(_ text: String) -> Text {
    Text(text).fontWeight(.medium).foregroundStyle(Tokens.foreground)
}

/// Meta parts set apart by " · ".
private func joined(_ parts: [Text]) -> Text {
    parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) { $0 + Text(verbatim: " · ") + $1 }
}

/// A tab's count, in mono beside its label.
struct TabCount: View {
    @Environment(AppModel.self) private var app
    let count: Int

    var body: some View {
        Text(app.t.number(count)).font(.vmMono(13)).foregroundStyle(Tokens.mutedForeground)
    }
}

/// A small heading over a run of rows: "Open now · 2", with the lock on what only the owner sees.
struct ProfileSection: View {
    @Environment(AppModel.self) private var app
    let label: String
    /// Left out while more pages remain, when the number would be wrong.
    let count: Int?
    var note: String?
    var onlyYou = false

    var body: some View {
        HStack(spacing: 6) {
            if onlyYou { OnlyYouMarker() }
            Text([label, count.map { app.t.number($0) }, note].compactMap { $0 }.joined(separator: " · "))
        }
        .font(.vm(12, .medium))
        .foregroundStyle(Tokens.mutedForeground)
        .padding(.top, 10)
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Edit profile (the web's `EditProfileDialog`): each detail says who sees it, and the owner changes that
/// right where they type. Details and visibility save together with Save.
struct EditProfileSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let profile: MyProfile
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var birthday: Date?
    @State private var visibility: [String: Bool] = [:]
    @State private var usernameError: String?
    /// A new username breaks old links, so it takes a second step.
    @State private var confirmingUsername = false
    @State private var isSaving = false
    @State private var showAvatar = false
    @FocusState private var usernameFocused: Bool

    private static let displayNameMax = 100
    private static let bioMax = 500
    private static let nameMax = 50
    private static let earliestBirthday = Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? .distantPast
    /// Yesterday as the API counts it: the earlier of the local and Taipei dates, minus a day.
    private static var latestBirthday: Date {
        var taipei = Calendar(identifier: .gregorian)
        taipei.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let today = [Calendar.current, taipei].map { cal -> Date in
            let c = cal.dateComponents([.year, .month, .day], from: .now)
            return Calendar.current.date(from: c) ?? .now
        }.min() ?? .now
        return Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
    }
    private static let birthdayFormat = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

    // The field lowercases, so a legacy mixed-case username isn't renamed by a case-only edit
    private var usernameChanged: Bool { username.lowercased() != profile.username.lowercased() }
    private var formattedBirthday: String? { birthday.map { $0.formatted(Self.birthdayFormat) } }
    // A birthday can't be cleared, so only one the user set counts
    private var birthdayChanged: Bool { formattedBirthday != nil && formattedBirthday != profile.birthday }
    private var detailsChanged: Bool {
        usernameChanged || birthdayChanged || displayName != (profile.displayName ?? "") || bio != (profile.bio ?? "")
            || firstName != (profile.firstName ?? "") || lastName != (profile.lastName ?? "")
    }
    /// "Your profile moves to /new. Links to /old stop working…"
    private var usernameMove: String {
        let paths: [String: CustomStringConvertible] = ["newPath": "/" + username, "oldPath": "/" + profile.username]
        return app.t("account.usernameConfirmBody", paths)
    }
    private var visibilityChanges: [String: Bool] {
        ProfileVisibility.changes(saved: profile.visibilitySettings, next: visibility)
    }

    var body: some View {
        NavigationStack {
            form
            .canvas()
            .navigationTitle(app.t("profile.editProfile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(app.t("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { saveButton }
            }
            .alert(app.t("account.usernameConfirmTitle"), isPresented: $confirmingUsername) {
                // The safe choice comes first
                Button(app.t("common.back"), role: .cancel) {}
                Button(app.t("account.usernameConfirmCta"), action: confirmUsername)
            } message: {
                Text(usernameMove)
            }
            .sheet(isPresented: $showAvatar) { AvatarPickerSheet(username: profile.username, avatarUrl: profile.avatarUrl) }
        }
        .onAppear(perform: start)
    }

    /// Each visit starts from the saved profile.
    private func start() {
        username = profile.username
        displayName = profile.displayName ?? ""
        bio = profile.bio ?? ""
        firstName = profile.firstName ?? ""
        lastName = profile.lastName ?? ""
        birthday = profile.birthday.flatMap { try? Date($0, strategy: Self.birthdayFormat) }
        visibility = profile.visibilitySettings
    }

    /// `text`, cut at `max` characters as the web's `maxLength` does.
    private func limited(_ text: Binding<String>, _ max: Int) -> Binding<String> {
        Binding(get: { text.wrappedValue }, set: { text.wrappedValue = String($0.prefix(max)) })
    }

    /// The username as typed, trimmed and lowercased like the web's field.
    private var usernameInput: Binding<String> {
        Binding(get: { username }, set: { value in
            username = String(value.trimmingCharacters(in: .whitespaces).lowercased().prefix(Username.maxLength))
            usernameError = nil
        })
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    AvatarView(username: profile.username, avatarUrl: profile.avatarUrl, size: 64)
                    Button(app.t("avatar.change")) { showAvatar = true }.buttonStyle(.vm(.outline, size: .sm))
                }

                groupLabel(app.t("profile.groupOnProfile"))
                VStack(alignment: .leading, spacing: 6) {
                    labelRow(app.t("profile.displayName")) { pill(app.t("profile.displayName"), ["displayName"]) }
                    VMTextField(label: nil, placeholder: app.t("profile.displayNamePlaceholder"), text: limited($displayName, Self.displayNameMax), contentType: .nickname)
                }
                .padding(.top, -8)
                usernameField
                VStack(alignment: .leading, spacing: 6) {
                    labelRow(app.t("profile.bio")) { pill(app.t("profile.bio"), ["bio"]) }
                    VMTextEditor(placeholder: app.t("profile.bioPlaceholder"), text: limited($bio, Self.bioMax), minHeight: 72)
                    Text("\(bio.count) / \(Self.bioMax)").font(.vmMono(12)).foregroundStyle(Tokens.mutedForeground)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                groupLabel(app.t("profile.groupAboutYou"))
                HStack(alignment: .top, spacing: 10) {
                    VMTextField(label: app.t("profile.firstName"), placeholder: "", text: limited($firstName, Self.nameMax), contentType: .givenName)
                    VMTextField(label: app.t("profile.lastName"), placeholder: "", text: limited($lastName, Self.nameMax), contentType: .familyName)
                }
                .padding(.top, -8)
                visibilityCard
            }
            .padding(Metrics.gutter)
        }
    }

    private var saveButton: some View {
        LoadingButton(style: .vm(.link), isLoading: isSaving, action: submit) {
            Text(app.t("common.save")).fontWeight(.semibold)
        }
    }

    /// Always shown, so no pill; a change warns that old links stop working.
    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            labelRow(app.t("account.usernameLabel")) {
                Text(app.t("profile.alwaysShown")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
            }
            HStack(spacing: 0) {
                Text(verbatim: "@").foregroundStyle(Tokens.mutedForeground).accessibilityHidden(true)
                TextField("", text: usernameInput)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($usernameFocused)
                    .accessibilityLabel(app.t("account.usernameLabel"))
            }
            .font(.vmMono(16))
            .fieldChrome(isFocused: usernameFocused, isInvalid: usernameError != nil)
            Group {
                if let usernameError {
                    Text(usernameError).foregroundStyle(Tokens.destructive)
                } else if usernameChanged, !username.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Tokens.foreground).accessibilityHidden(true)
                        Text(usernameMove)
                    }
                    .foregroundStyle(Tokens.mutedForeground)
                } else {
                    Text(app.t("account.usernameHint", ["path": "/\(username.isEmpty ? profile.username : username)"]))
                        .foregroundStyle(Tokens.mutedForeground)
                }
            }
            .font(.vm(12))
        }
    }

    /// Real name, birthday, location, points and membership level, each with who sees it.
    private var visibilityCard: some View {
        VStack(spacing: 0) {
            visibilityRow(app.t("profile.realName")) { pill(app.t("profile.realName"), ["firstName", "lastName"]) }
            Hairline()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.t("profile.birthday")).font(.vm(14))
                    if birthday == nil {
                        Button(app.t("ios.setBirthday")) { birthday = Self.latestBirthday }.buttonStyle(.vm(.link))
                    } else {
                        DatePicker(
                            app.t("profile.birthday"),
                            selection: Binding(get: { birthday ?? .now }, set: { birthday = $0 }),
                            in: Self.earliestBirthday...Self.latestBirthday,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The API never shows a birthday to anyone else
                VisibilityPill(isPublic: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 52)
            Hairline()
            visibilityRow(app.t("account.field.location"), value: profile.location) {
                pill(app.t("account.field.location"), ["location"])
            }
            Hairline()
            visibilityRow(app.t("account.field.points"), value: app.t.number(profile.points), mono: true) {
                pill(app.t("account.field.points"), ["points"], plural: true)
            }
            Hairline()
            visibilityRow(app.t("account.field.membershipLevel"), value: profile.membershipLevel) {
                pill(app.t("account.field.membershipLevel"), ["membershipLevel"])
            }
        }
        .card(padding: nil)
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text).font(.vm(12, .medium)).foregroundStyle(Tokens.mutedForeground)
            .padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func labelRow(_ label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.vm(14, .medium)).foregroundStyle(Tokens.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: 28)
    }

    /// A detail that isn't edited here: its label, then its value or "Not set".
    private func visibilityRow(_ label: String, value: String?? = .none, mono: Bool = false, @ViewBuilder pill: () -> some View) -> some View {
        HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.vm(14)).foregroundStyle(Tokens.foreground)
                if let value {
                    Text(value.flatMap { $0.isEmpty ? nil : $0 } ?? app.t("profile.notSet"))
                        .font(mono ? .vmMono(12) : .vm(12)).foregroundStyle(Tokens.mutedForeground).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            pill()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    /// Who sees `fields`, switching all of them between Everyone and Only you.
    private func pill(_ label: String, _ fields: [String], plural: Bool = false) -> some View {
        let isPublic = ProfileVisibility.isPublic(visibility, fields[0])
        let key = switch (isPublic, plural) {
        case (true, false): "profile.visibilityPillEveryone"
        case (true, true): "profile.visibilityPillEveryonePlural"
        case (false, false): "profile.visibilityPillOnlyYou"
        case (false, true): "profile.visibilityPillOnlyYouPlural"
        }
        return Button {
            for field in fields { visibility[field] = !isPublic }
        } label: {
            VisibilityPill(isPublic: isPublic, canChange: true)
                .frame(minHeight: Metrics.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.t(key, ["field": label]))
    }

    private func showUsernameError(_ message: String) {
        usernameError = message
        usernameFocused = true
    }

    private func submit() async {
        if usernameChanged, !Username.isValid(username) {
            // A reserved name already fits the format, so it gets its own reason
            showUsernameError(Username.reserved.contains(username)
                ? app.t("account.usernameReserved", ["username": username])
                : app.t("account.usernameInvalid"))
            return
        }
        if !detailsChanged, visibilityChanges.isEmpty { dismiss(); return }
        if usernameChanged { confirmingUsername = true } else { await save() }
    }

    private func confirmUsername() {
        Task { await save() }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let savingDetails = detailsChanged
        let changes = visibilityChanges
        if savingDetails {
            do {
                try await app.service.updateProfile(
                    username: usernameChanged ? username : nil, displayName: displayName, bio: bio,
                    firstName: firstName != (profile.firstName ?? "") ? firstName : nil,
                    lastName: lastName != (profile.lastName ?? "") ? lastName : nil,
                    birthday: birthdayChanged ? formattedBirthday : nil
                )
            } catch {
                // A refused username belongs next to its field; anything else is a toast
                if usernameChanged, (error as? APIError)?.errorCode == "user.username.taken" {
                    showUsernameError(app.t.message(for: error, fallback: "account.saveFailed"))
                } else {
                    app.showToast(app.t.message(for: error, fallback: "account.saveFailed"), isError: true)
                }
                return
            }
            app.updateMe {
                if usernameChanged { $0.username = username }
                $0.displayName = displayName.isEmpty ? nil : displayName
                $0.bio = bio.isEmpty ? nil : bio
                $0.firstName = firstName.isEmpty ? nil : firstName
                $0.lastName = lastName.isEmpty ? nil : lastName
                if birthdayChanged { $0.birthday = formattedBirthday }
            }
        }
        if !changes.isEmpty {
            do {
                let settings = try await app.service.updateVisibility(changes)
                app.updateMe { $0.visibilitySettings = settings }
            } catch {
                // Stays open so the visibility can be saved again; the details no longer count as changed
                app.showToast(app.t(savingDetails ? "profile.visibilitySaveFailed" : "account.saveFailed"), isError: true)
                return
            }
        }
        app.showToast(app.t("profile.updated"))
        dismiss()
    }
}

/// Who sees a profile detail: Everyone (globe) or Only you (lock); a chevron when it can be changed.
struct VisibilityPill: View {
    @Environment(AppModel.self) private var app
    let isPublic: Bool
    var canChange = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: isPublic ? "globe" : "lock.fill").font(.system(size: 10, weight: .semibold))
            Text(app.t(isPublic ? "profile.everyone" : "profile.onlyYouShort"))
            if canChange { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }
        }
        .font(.vm(12, .medium))
        .foregroundStyle(isPublic ? Tokens.foreground : Tokens.mutedForeground)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(isPublic ? Tokens.card : Tokens.secondary, in: Capsule())
        .overlay(Capsule().strokeBorder(isPublic ? Tokens.borderStrong : Tokens.border))
        .fixedSize()
    }
}

/// The bot cast, in four families (the web's `AvatarDialog`).
struct AvatarPickerSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let username: String
    let avatarUrl: String?
    @State private var selected = ""
    private var initial: String { Avatars.resolve(username: username, avatarUrl: avatarUrl) }

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
        .onAppear { selected = initial }
    }

    private func save() async {
        // Saving an untouched picker must not turn `bot:none` into the hash-derived bot.
        if Avatars.isNone(avatarUrl), selected == initial { dismiss(); return }
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

import SwiftUI
import VomattCore

/// Picks people by username (search) or email, and Groups whose members are copied in (the web's `InviteePicker`).
struct InviteePicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: InviteeSelection
    var withGroups = false
    var isInvalid = false

    /// Search results, tagged with the term they answer so stale ones never show.
    private struct Results { var term = ""; var users: [UserSummary] = []; var failed = false }

    @State private var query = ""
    @State private var results = Results()
    @State private var groups: [UserGroup] = []

    private static let maxSuggestions = 5

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var email: String { Email.normalize(term) }
    private var isEmail: Bool { Email.isValid(email) }
    private var isSearching: Bool { !term.isEmpty && !term.contains("@") }
    private var isLoading: Bool { isSearching && results.term != term }
    private var suggestions: [UserSummary] {
        guard isSearching, results.term == term else { return [] }
        return Array(results.users.filter { user in !selection.users.contains { $0.id == user.id } && user.id != app.userId }
            .prefix(Self.maxSuggestions))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if withGroups, !groups.isEmpty { groupPills }
            VStack(alignment: .leading, spacing: 4) {
                SearchField(placeholder: app.t("invitees.placeholder"), text: $query)
                    .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(isInvalid ? Tokens.destructive : .clear))
                    .onSubmit {
                        // Return picks the email, or the first person found
                        if isEmail { addEmail() } else if let first = suggestions.first { add(first) }
                    }
                if isEmail {
                    Button(action: addEmail) {
                        Label(app.t("invitees.inviteEmail", ["email": email]), systemImage: "envelope")
                            .frame(maxWidth: .infinity, minHeight: Metrics.minTarget, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .font(.vm(14))
                }
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 8)
                } else if !suggestions.isEmpty {
                    suggestionList
                } else if isSearching {
                    Text(app.t(results.failed ? "invitees.searchFailed" : "invitees.noUsers"))
                        .font(.vm(12)).foregroundStyle(Tokens.mutedForeground).padding(.vertical, 8)
                }
            }
            if !chips.isEmpty { picked }
        }
        .task(id: isSearching ? term : "") { await search() }
        .task { if withGroups { groups = (try? await app.service.groups()) ?? [] } }
    }

    private var groupPills: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(app.t("invitees.groups")).font(.vm(12)).foregroundStyle(Tokens.mutedForeground)
            FlowLayout(spacing: 8) {
                ForEach(groups) { group in
                    let isOn = selection.groups.contains { $0.id == group.id }
                    Button {
                        if isOn { selection.groups.removeAll { $0.id == group.id } }
                        else { selection.groups.append(.init(id: group.id, name: group.name, memberCount: group.memberCount)) }
                    } label: {
                        HStack(spacing: 4) {
                            Text(group.name)
                            Text("\(group.memberCount)").font(.vmMono(13)).monospacedDigit()
                        }
                    }
                    .buttonStyle(.vm(isOn ? .default : .outline, size: .sm, pill: true))
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    // The count is set apart visually; the label says what it counts
                    .accessibilityLabel(app.t("invitees.groupPill", ["name": group.name, "count": group.memberCount]))
                }
            }
        }
    }

    private struct PickedChip: Identifiable {
        let id: String
        let label: String
        var user: InviteeSelection.User?
        let remove: () -> Void
    }

    private var chips: [PickedChip] {
        selection.users.map { user in
            PickedChip(id: "user:\(user.id)", label: user.username, user: user) { selection.users.removeAll { $0.id == user.id } }
        }
        + selection.emails.map { address in
            PickedChip(id: "email:\(address)", label: address) { selection.emails.removeAll { $0 == address } }
        }
        // A picked Group without a pill: deleted since a draft was saved, or Groups didn't load
        + selection.groups.filter { picked in !groups.contains { $0.id == picked.id } }.map { group in
            PickedChip(id: "group:\(group.id)", label: group.name) { selection.groups.removeAll { $0.id == group.id } }
        }
    }

    private var picked: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips) { chip in
                HStack(spacing: 4) {
                    if let user = chip.user {
                        AvatarView(username: user.username, avatarUrl: user.avatarUrl, size: 24).padding(.leading, -6)
                    }
                    Text(chip.label).font(.vm(12)).lineLimit(1)
                    Button(action: chip.remove) {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Tokens.mutedForeground)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(app.t("invitees.remove", ["name": chip.label]))
                }
                .foregroundStyle(Tokens.foreground)
                .padding(.leading, 12)
                .frame(minHeight: 32)
                .background(Tokens.secondary, in: Capsule())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.t("invitees.picked"))
    }

    private var suggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions) { user in
                Button { add(user) } label: {
                    HStack(spacing: 12) {
                        AvatarView(username: user.username, avatarUrl: user.avatarUrl, size: 28)
                        Text(user.username).font(.vm(14)).lineLimit(1)
                        if let name = user.displayName {
                            Text(name).font(.vm(12)).foregroundStyle(Tokens.mutedForeground).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Tokens.foreground)
                    .frame(minHeight: Metrics.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.t("invitees.suggestions"))
    }

    private func add(_ user: UserSummary) {
        selection.users.append(.init(id: user.id, username: user.username, avatarUrl: user.avatarUrl))
        query = ""
    }

    private func addEmail() {
        if !selection.emails.contains(email) { selection.emails.append(email) }
        query = ""
    }

    private func search() async {
        let term = term
        guard isSearching else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let users = try await app.service.searchUsers(term, limit: 8).items
            results = Results(term: term, users: users)
        } catch {
            if !(error is CancellationError) { results = Results(term: term, failed: true) }
        }
    }
}

/// The owner's Invitee list for an Invite-only Poll (the web's `InviteeManager`).
struct InviteeManagerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let pollId: String
    let onChanged: ([Invitee]) -> Void

    @State private var invitees: [Invitee]?
    @State private var failed = false
    @State private var adding = InviteeSelection()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(app.t("invitees.description")).font(.vmBody).foregroundStyle(Tokens.mutedForeground)
                    if let invitees {
                        Text(app.t("invitees.summary", ["count": invitees.count, "voted": invitees.filter(\.hasBallot).count]))
                            .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                        if invitees.isEmpty {
                            EmptyState { Text(app.t("invitees.empty")) }
                        } else {
                            VStack(spacing: 0) {
                                ForEach(invitees) { invitee in row(invitee) }
                            }
                            .card(padding: nil)
                        }
                    } else if failed {
                        LoadFailed(message: app.t("invitees.loadFailed")) { await load() }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: app.t("invitees.addLabel"))
                        InviteePicker(selection: $adding, withGroups: true)
                        LoadingButton(style: .vm(.default, fullWidth: true), action: add) { Text(app.t("invitees.add")) }
                            .disabled(adding.isEmpty)
                    }
                }
                .padding(Metrics.gutter)
            }
            .canvas()
            .navigationTitle(app.t("invitees.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(app.t("common.close")) { dismiss() } } }
        }
        .task { await load() }
    }

    private func row(_ invitee: Invitee) -> some View {
        let name = invitee.person.username ?? invitee.person.email ?? ""
        return HStack(spacing: 10) {
            if let username = invitee.person.username {
                AvatarView(username: username, avatarUrl: invitee.person.avatarUrl, size: 28)
            } else {
                Image(systemName: "envelope").frame(width: 28, height: 28).background(Tokens.secondary, in: Circle())
            }
            Text(name).font(.vm(15)).lineLimit(1)
            Spacer()
            if invitee.hasBallot {
                Chip(text: app.t("invitees.voted"), tint: Tokens.statusOpen)
            } else {
                Button { Task { await remove(invitee) } } label: { Image(systemName: "xmark") }
                    .buttonStyle(.vm(.ghost, size: .icon))
                    .foregroundStyle(Tokens.mutedForeground)
                    .accessibilityLabel(app.t("invitees.remove", ["name": name]))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func load() async {
        do {
            invitees = try await app.service.invitees(pollId: pollId)
            failed = false
        } catch {
            failed = true
        }
    }

    private func add() async {
        do {
            let list = try await app.service.addInvitees(pollId: pollId, adding.input)
            invitees = list
            adding = InviteeSelection()
            onChanged(list)
        } catch {
            app.showToast(app.t.message(for: error, fallback: "invitees.addFailed"), isError: true)
        }
    }

    private func remove(_ invitee: Invitee) async {
        do {
            let list = try await app.service.removeInvitee(pollId: pollId, invitee.person)
            invitees = list
            onChanged(list)
        } catch {
            app.showToast(app.t.message(for: error, fallback: "invitees.removeFailed"), isError: true)
        }
    }
}

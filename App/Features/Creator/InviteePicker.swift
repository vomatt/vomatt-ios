import SwiftUI
import VomattCore

/// Picks people by username or email, and Groups whose members are copied in (the web's `InviteePicker`).
struct InviteePicker: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: InviteeSelection
    var withGroups = false
    var isInvalid = false

    @State private var query = ""
    @State private var suggestions: [UserSummary] = []
    @State private var searchFailed = false
    @State private var groups: [UserGroup] = []

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var queryIsEmail: Bool { Email.isValid(trimmed) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selection.isEmpty { picked }
            SearchField(placeholder: app.t("invitees.placeholder"), text: $query)
                .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(isInvalid ? Tokens.destructive : .clear))
            if queryIsEmail {
                Button { addEmail(Email.normalize(trimmed)) } label: {
                    Label(app.t("invitees.inviteEmail", ["email": Email.normalize(trimmed)]), systemImage: "envelope")
                }
                .buttonStyle(.vm(.outline, size: .sm))
            } else if trimmed.count >= 2 {
                suggestionList
            }
            if withGroups, !groups.isEmpty {
                Text(app.t("invitees.groups")).font(.vm(13, .medium)).foregroundStyle(Tokens.mutedForeground)
                FlowLayout(spacing: 6) {
                    ForEach(groups) { group in
                        let isOn = selection.groups.contains { $0.id == group.id }
                        PillButton(title: app.t("invitees.groupPill", ["name": group.name, "count": group.memberCount]), isOn: isOn) {
                            if isOn { selection.groups.removeAll { $0.id == group.id } }
                            else { selection.groups.append(.init(id: group.id, name: group.name, memberCount: group.memberCount)) }
                        }
                    }
                }
            }
        }
        .task(id: trimmed) { await search() }
        .task { if withGroups { groups = (try? await app.service.groups()) ?? [] } }
    }

    private var picked: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(app.t("invitees.picked")).font(.vm(13, .medium)).foregroundStyle(Tokens.mutedForeground)
            FlowLayout(spacing: 6) {
                ForEach(selection.users) { user in
                    removable(user.username, avatar: AvatarView(username: user.username, avatarUrl: user.avatarUrl, size: 20)) {
                        selection.users.removeAll { $0.id == user.id }
                    }
                }
                ForEach(selection.emails, id: \.self) { email in
                    removable(email, avatar: Image(systemName: "envelope").font(.system(size: 12))) {
                        selection.emails.removeAll { $0 == email }
                    }
                }
                ForEach(selection.groups) { group in
                    removable(app.t("invitees.groupPill", ["name": group.name, "count": group.memberCount]),
                              avatar: Image(systemName: "person.2").font(.system(size: 12))) {
                        selection.groups.removeAll { $0.id == group.id }
                    }
                }
            }
        }
    }

    private func removable(_ name: String, avatar: some View, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 6) {
                avatar
                Text(name).font(.vm(14)).lineLimit(1)
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Tokens.mutedForeground)
            }
            .foregroundStyle(Tokens.foreground)
            .padding(.leading, 6).padding(.trailing, 10)
            .frame(minHeight: 32)
            .background(Tokens.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.t("invitees.remove", ["name": name]))
    }

    @ViewBuilder private var suggestionList: some View {
        if searchFailed {
            Text(app.t("invitees.searchFailed")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
        } else if suggestions.isEmpty {
            Text(app.t("invitees.noUsers")).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text(app.t("invitees.suggestions")).font(.vm(13, .medium)).foregroundStyle(Tokens.mutedForeground).padding(.bottom, 4)
                ForEach(suggestions.filter { user in !selection.users.contains { $0.id == user.id } && user.id != app.userId }) { user in
                    Button {
                        selection.users.append(.init(id: user.id, username: user.username, avatarUrl: user.avatarUrl))
                        query = ""
                    } label: {
                        HStack {
                            UserChip(username: user.username, avatarUrl: user.avatarUrl, label: user.displayName.map { "\($0) · @\(user.username)" },
                                     avatarSize: 28, link: false)
                                .font(.vm(15))
                                .foregroundStyle(Tokens.foreground)
                            Spacer()
                            Image(systemName: "plus").foregroundStyle(Tokens.mutedForeground)
                        }
                        .frame(minHeight: Metrics.minTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addEmail(_ email: String) {
        if !selection.emails.contains(email) { selection.emails.append(email) }
        query = ""
    }

    private func search() async {
        let q = trimmed
        guard q.count >= 2, !Email.isValid(q) else {
            suggestions = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            suggestions = try await app.service.searchUsers(q.hasPrefix("@") ? String(q.dropFirst()) : q, limit: 8).items
            searchFailed = false
        } catch {
            searchFailed = !(error is CancellationError)
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
        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.border).frame(height: 1) }
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

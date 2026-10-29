import SwiftUI
import VomattCore

/// Reusable invite lists for Invite-only Polls (the web's `GroupsPanel`).
struct GroupsPanel: View {
    @Environment(AppModel.self) private var app
    @State private var groups: [UserGroup]?
    @State private var failed = false
    @State private var newName = ""
    @State private var editing: UserGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(app.t("groups.intro")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            HStack(alignment: .bottom, spacing: 8) {
                VMTextField(label: app.t("groups.nameLabel"), placeholder: app.t("groups.namePlaceholder"), text: $newName)
                LoadingButton(style: .vm(.default), action: create) { Text(app.t("groups.create")) }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let groups {
                if groups.isEmpty {
                    EmptyState { Text(app.t("groups.empty")) }
                } else {
                    VStack(spacing: 8) {
                        ForEach(groups) { group in
                            Button { editing = group } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.name).font(.vm(16, .medium)).foregroundStyle(Tokens.foreground)
                                        Text(memberCount(group.memberCount)).font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Tokens.mutedForeground)
                                }
                                .card()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else if failed {
                LoadFailed(message: app.t("groups.loadFailed")) { await load() }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .task { await load() }
        .sheet(item: $editing) { group in
            GroupEditor(group: group) { change in
                switch change {
                case let .updated(updated): groups = groups?.map { $0.id == updated.id ? updated : $0 }
                case let .deleted(id): groups?.removeAll { $0.id == id }
                }
            }
        }
    }

    private func memberCount(_ count: Int) -> String {
        count == 1 ? app.t("groups.memberCountOne") : app.t("groups.memberCount", ["count": count])
    }

    private func load() async {
        do {
            groups = try await app.service.groups()
            failed = false
        } catch {
            failed = true
        }
    }

    private func create() async {
        let name = String(newName.trimmingCharacters(in: .whitespaces).prefix(groupNameMax))
        do {
            let group = try await app.service.createGroup(name: name)
            groups = ((groups ?? []) + [group]).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            newName = ""
            editing = group
        } catch {
            app.showToast(app.t.message(for: error, fallback: "groups.saveFailed"), isError: true)
        }
    }
}

/// Rename, members and delete for one Group.
private struct GroupEditor: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    enum Change { case updated(UserGroup), deleted(String) }

    @State var group: UserGroup
    let onChange: (Change) -> Void
    @State private var name = ""
    @State private var members: [GroupMember]?
    @State private var failed = false
    @State private var adding = InviteeSelection()
    @State private var confirmingDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(app.t("groups.dialogIntro")).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
                    HStack(alignment: .bottom, spacing: 8) {
                        VMTextField(label: app.t("groups.nameLabel"), placeholder: app.t("groups.namePlaceholder"), text: $name)
                        LoadingButton(style: .vm(.outline), action: rename) { Text(app.t("groups.rename")) }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == group.name)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: app.t("groups.members"))
                        if let members {
                            if members.isEmpty {
                                EmptyState { Text(app.t("groups.noMembers")) }
                            } else {
                                VStack(spacing: 0) { ForEach(members) { row($0) } }.card(padding: nil)
                            }
                        } else if failed {
                            LoadFailed(message: app.t("groups.membersFailed")) { await load() }
                        } else {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(text: app.t("groups.addLabel"))
                        InviteePicker(selection: $adding)
                        LoadingButton(style: .vm(.default, fullWidth: true), action: add) { Text(app.t("groups.add")) }
                            .disabled(adding.isEmpty)
                    }
                    Button(app.t("groups.delete")) { confirmingDelete = true }
                        .buttonStyle(.vm(.destructive, fullWidth: true))
                }
                .padding(Metrics.gutter)
            }
            .canvas()
            .navigationTitle(group.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(app.t("common.close")) { dismiss() } } }
            .confirmationDialog(app.t("groups.deleteConfirm"), isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button(app.t("groups.delete"), role: .destructive) { Task { await delete() } }
            }
        }
        .onAppear { name = group.name }
        .task { await load() }
    }

    private func row(_ member: GroupMember) -> some View {
        let label = member.person.username ?? member.person.email ?? ""
        return HStack(spacing: 10) {
            if let username = member.person.username {
                AvatarView(username: username, avatarUrl: member.person.avatarUrl, size: 28)
            } else {
                Image(systemName: "envelope").frame(width: 28, height: 28).background(Tokens.secondary, in: Circle())
            }
            Text(label).font(.vm(15)).lineLimit(1)
            Spacer()
            Button { Task { await remove(member) } } label: { Image(systemName: "xmark") }
                .buttonStyle(.vm(.ghost, size: .icon))
                .foregroundStyle(Tokens.mutedForeground)
                .accessibilityLabel(app.t("invitees.remove", ["name": label]))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func load() async {
        do {
            members = try await app.service.groupMembers(groupId: group.id)
            failed = false
        } catch {
            failed = true
        }
    }

    private func setMembers(_ list: [GroupMember]) {
        members = list
        group.memberCount = list.count
        onChange(.updated(group))
    }

    private func rename() async {
        do {
            group = try await app.service.renameGroup(id: group.id, name: String(name.prefix(groupNameMax)))
            onChange(.updated(group))
        } catch {
            app.showToast(app.t.message(for: error, fallback: "groups.saveFailed"), isError: true)
        }
    }

    private func add() async {
        do {
            setMembers(try await app.service.addGroupMembers(groupId: group.id, userIds: adding.users.map(\.id), emails: adding.emails))
            adding = InviteeSelection()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "groups.saveFailed"), isError: true)
        }
    }

    private func remove(_ member: GroupMember) async {
        do {
            setMembers(try await app.service.removeGroupMember(groupId: group.id, member.person))
        } catch {
            app.showToast(app.t.message(for: error, fallback: "groups.saveFailed"), isError: true)
        }
    }

    private func delete() async {
        do {
            try await app.service.deleteGroup(id: group.id)
            onChange(.deleted(group.id))
            dismiss()
        } catch {
            app.showToast(app.t.message(for: error, fallback: "groups.saveFailed"), isError: true)
        }
    }
}

import SwiftUI
import VomattCore

/// A community account's invitation, answered on its own screen (the web's `CommunityInvitationCard`):
/// the account, the role offered, who sent it and until when, with Accept and Decline. An answer says
/// what happened in a toast, drops the row from the feed and goes back.
struct CommunityInvitationView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let invitationId: String

    /// `unavailable`: the API won't show it (expired, withdrawn, answered, or sent to another address).
    private enum Phase { case loading, failed, unavailable, pending(CommunityInvitationDetail) }
    private enum Answer { case accept, decline }

    @State private var phase = Phase.loading
    /// The answer on its way; both buttons wait for it.
    @State private var answering: Answer?

    var body: some View {
        ScrollView {
            content
                .pageColumn()
                .padding(.vertical, 24)
        }
        .canvas()
        .navigationTitle(app.t("communities.invitationPage.title"))
        .navigationBarTitleDisplayMode(.inline)
        // Signing in as the invited account is what makes an unavailable invitation show
        .task(id: app.sessionGeneration) { await load() }
    }

    @ViewBuilder private var content: some View {
        if !app.isSignedIn {
            LoginPromptCard()
        } else {
            switch phase {
            case .loading:
                Skeleton(height: 320, radius: Radius.card)
            case .failed:
                LoadFailed(message: app.t("common.error")) { await load() }
            case .unavailable:
                unavailable
            case let .pending(invitation):
                pending(invitation)
            }
        }
    }

    private func pending(_ invitation: CommunityInvitationDetail) -> some View {
        let community = invitation.community
        let name = community.displayName ?? community.username
        let role = invitation.role.rawValue
        let meta = [
            invitation.inviter.map { app.t("communities.invitationPage.invitedBy", ["name": ProfileName.handle($0.username)]) },
            app.t("communities.invitationPage.expires", ["date": app.dates.day(invitation.expiresAt)]),
        ].compactMap { $0 }
        return VStack(spacing: 12) {
            AvatarView(username: community.username, avatarUrl: community.avatarUrl, size: 56)
            VStack(spacing: 4) {
                Text(app.t("communities.invitationPage.pendingTitle", ["name": name]))
                    .displayHeading(22)
                    .accessibilityAddTraits(.isHeader)
                Text(ProfileName.handle(community.username)).font(.vm(14)).foregroundStyle(Tokens.mutedForeground)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(app.t("communities.invitationPage.role", ["role": app.t("communities.roles.\(role)")]))
                    .font(.vm(16, .medium)).foregroundStyle(Tokens.foreground)
                Text(app.t("communities.roleBodies.\(role)"))
                    .font(.vmMeta).foregroundStyle(Tokens.mutedForeground)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Tokens.border))
            Text(meta.joined(separator: metaGap))
                .font(.vm(12, relativeTo: .caption)).foregroundStyle(Tokens.mutedForeground)
            if invitation.isLocked {
                Text(app.t("communities.invitationPage.locked", ["name": name]))
                    .font(.vm(14)).foregroundStyle(Tokens.foreground)
            }
            HStack(spacing: 8) {
                LoadingButton(style: .vm(.default), isLoading: answering == .accept, action: { await answer(.accept, invitation) }) {
                    Text(app.t("notifications.accept"))
                }
                .disabled(invitation.isLocked || answering != nil)
                LoadingButton(style: .vm(.outline), isLoading: answering == .decline, action: { await answer(.decline, invitation) }) {
                    Text(app.t("notifications.decline"))
                }
                .disabled(answering != nil)
            }
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 40)
        .card(padding: nil)
    }

    private var unavailable: some View {
        let signedInAs = app.me.map { app.t("communities.invitationPage.signedInAs", ["account": $0.email ?? ProfileName.handle($0.username)]) }
        return EmptyCard(
            title: app.t("communities.invitationPage.unavailableTitle"),
            body: [app.t("communities.invitationPage.unavailableBody"), signedInAs].compactMap { $0 }.joined(separator: " ")
        ) {
            VStack(spacing: 8) {
                // The invitation may be for another of the person's accounts; signed in as it, this screen loads again
                LoadingButton(style: .vm(.default), action: {
                    await app.signOut()
                    app.signIn()
                }) {
                    Text(app.t("communities.invitationPage.useDifferentAccount"))
                }
                Button(app.t("common.notifications")) { app.select(.notifications) }
                    .buttonStyle(.vm(.outline))
            }
        }
    }

    private func load() async {
        guard app.isSignedIn else { return }
        if case .pending = phase {} else { phase = .loading }
        do {
            if let invitation = try await app.service.communityInvitation(id: invitationId) {
                phase = .pending(invitation)
            } else {
                close()
            }
        } catch {
            if case .pending = phase { return }
            phase = .failed
        }
    }

    private func answer(_ answer: Answer, _ invitation: CommunityInvitationDetail) async {
        answering = answer
        defer { answering = nil }
        do {
            switch answer {
            case .accept: try await app.service.acceptCommunityInvitation(id: invitation.id)
            case .decline: try await app.service.declineCommunityInvitation(id: invitation.id)
            }
        } catch let error as APIError where error.isCommunityInvitationGone {
            return close()
        } catch {
            // Locked, or an owner invitation over the invitee's plan: it stays open to answer later
            return app.showToast(app.t.message(for: error, fallback: "common.error"), isError: true)
        }
        let name = ProfileName.handle(invitation.community.username)
        app.showToast(app.t(answer == .accept ? "notifications.invitationAccepted" : "notifications.invitationDeclined", ["name": name]))
        app.didCloseCommunityInvitation(invitation.id)
        dismiss()
    }

    /// Nothing left to answer: the screen says so, and the feed's row goes.
    private func close() {
        phase = .unavailable
        app.didCloseCommunityInvitation(invitationId)
    }
}

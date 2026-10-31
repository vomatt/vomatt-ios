import Foundation
import Testing
@testable import VomattCore

// Cases ported from vomatt-web's src/__tests__/features/polls/status.test.ts

private let now = ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")!
private func hours(_ h: Double) -> Date { now.addingTimeInterval(h * 3600) }

private func poll(
    active: Bool = true, votingActive: Bool = true, start: Date = hours(-48), end: Date? = hours(72),
    audience: Audience? = .public, visibility: VoterVisibility? = .owner, deletable: Bool? = nil,
    options: [PollOption] = [PollOption(id: "a", text: "A"), PollOption(id: "b", text: "B")],
    myOptionId: String? = nil, participants: Int? = nil, deadline: Date? = nil
) -> Poll {
    Poll(
        id: "p1", title: "Q", active: active, votingActive: votingActive, voterVisibility: visibility,
        audience: audience, creatorId: "owner", creatorUsername: "alice", createdAt: start, startTime: start,
        endTime: end, deadline: deadline, deletable: deletable,
        participantCount: participants, myOptionId: myOptionId, options: options
    )
}

@Suite("Poll status")
struct PollStatusTests {
    @Test func openBetweenStartAndEnd() { #expect(poll().status(at: now) == .open) }
    @Test func closingUnder24h() { #expect(poll(end: hours(5)).status(at: now) == .closing) }
    @Test func scheduledBeforeStart() { #expect(poll(votingActive: false, start: hours(48)).status(at: now) == .scheduled) }
    @Test func endedOnceEndPasses() { #expect(poll(end: hours(-1)).status(at: now) == .ended) }
    @Test func endedWhenClosedEarly() { #expect(poll(active: false).status(at: now) == .ended) }
    @Test func endedWhenVotingInactiveAfterStart() { #expect(poll(votingActive: false).status(at: now) == .ended) }
    @Test func endedWinsOverScheduled() {
        #expect(poll(active: false, votingActive: false, start: hours(48)).status(at: now) == .ended)
    }
    @Test func noEndTimeIsOpen() { #expect(poll(end: nil).status(at: now) == .open) }
}

@Suite("Poll helpers")
struct PollHelperTests {
    @Test func turnoutIsTheParticipantCount() {
        #expect(poll(participants: 4).turnout == 4)
        #expect(poll().turnout == nil)
    }

    @Test func cancelledWhenEndIsNotAfterStart() {
        #expect(poll(start: hours(1), end: hours(1)).isCancelled)
        #expect(!poll().isCancelled)
    }

    @Test func inviteOnlySignedInReadsAsInvited() {
        #expect(poll(audience: .inviteOnly, visibility: .signedIn).visibilityLevel == .invited)
        #expect(poll(audience: .public, visibility: .signedIn).visibilityLevel == .signedIn)
    }

    @Test func otherViewersOfInviteOnlyAreInvitees() {
        #expect(poll(audience: .inviteOnly).isInvitee(viewerId: "someone"))
        #expect(!poll(audience: .inviteOnly).isInvitee(viewerId: "owner"))
        #expect(!poll(audience: .public).isInvitee(viewerId: "someone"))
    }

    @Test func endedEarlyComparesDeadline() {
        #expect(poll(end: hours(-2), deadline: hours(10)).endedEarly)
        #expect(!poll(end: hours(10), deadline: hours(10)).endedEarly)
    }

    @Test func timelineProgressIsClamped() {
        #expect(poll(start: hours(-1), end: hours(1)).timelineProgress(at: now) == 50)
        #expect(poll(start: hours(-3), end: hours(-1)).timelineProgress(at: now) == 100)
        #expect(poll(end: nil).timelineProgress(at: now) == nil)
    }

    @Test func ownerActionsFollowStatusAndAudience() {
        let scheduled = poll(start: hours(2), end: hours(30)).ownerActions(at: now)
        #expect(scheduled.canEdit && scheduled.canDelete && !scheduled.canEnd)
        let publicOpen = poll().ownerActions(at: now)
        #expect(!publicOpen.any)
        let unlistedOpen = poll(audience: .unlisted).ownerActions(at: now)
        #expect(unlistedOpen.canEnd && !unlistedOpen.canEdit)
        let invite = poll(audience: .inviteOnly).ownerActions(at: now)
        #expect(invite.canInvite && invite.canEnd)
        #expect(poll(deletable: true).ownerActions(at: now).canDelete)
    }

    @Test func votersFollowVisibility() {
        #expect(poll(visibility: .signedIn).canSeeVoters(viewerId: "x"))
        #expect(!poll(visibility: .signedIn).canSeeVoters(viewerId: nil))
        #expect(poll(visibility: .owner).canSeeVoters(viewerId: "owner"))
        #expect(!poll(visibility: .owner).canSeeVoters(viewerId: "x"))
        #expect(!poll(visibility: .nobody).canSeeVoters(viewerId: "owner"))
    }

    // vomatt-web's Ballot: no anonymity switch on Polls whose voters nobody can see
    @Test func anonymityOnlyWhereSomeoneSeesVoters() {
        #expect(!poll(visibility: .nobody).allowsAnonymousBallot)
        #expect(poll(visibility: .owner).allowsAnonymousBallot)
        #expect(poll(visibility: .signedIn).allowsAnonymousBallot)
    }
}

@Suite("Results")
struct ResultsTests {
    @Test func winnersAreTheTopRows() {
        let rows = [ResultRow(id: "a", text: "A", votes: 3), ResultRow(id: "b", text: "B", votes: 3), ResultRow(id: "c", text: "C", votes: 1)]
        #expect(Results.winners(rows).map(\.id) == ["a", "b"])
        #expect(Results.winners([ResultRow(id: "a", text: "A", votes: 0)]).isEmpty)
    }

    @Test func supportRoundsAndHandlesZero() {
        #expect(Results.support(votes: 1, participants: 3) == 33)
        #expect(Results.support(votes: 2, participants: 3) == 67)
        #expect(Results.support(votes: 0, participants: 0) == 0)
    }

    @Test func inlineResultsNeedEveryCount() {
        #expect(poll().inlineResults == nil)
        let counted = poll(options: [PollOption(id: "a", text: "A", votes: 2), PollOption(id: "b", text: "B", votes: 0)])
        #expect(counted.inlineResults?.map(\.votes) == [2, 0])
    }

    @Test func shiftCountNeverGoesNegative() {
        #expect(shiftCount(0, by: -1) == 0)
        #expect(shiftCount(nil, by: 1) == nil)
        #expect(shiftCount(2, by: 1) == 3)
    }
}

// Cases ported from vomatt-web's src/__tests__/features/account/insights.test.ts
@Suite("Account insights")
struct InsightsTests {
    private func counted(_ a: Int?, _ b: Int?, ended: Bool = true) -> Poll {
        poll(end: hours(ended ? -1 : 72), options: [PollOption(id: "a", text: "A", votes: a), PollOption(id: "b", text: "B", votes: b)])
    }

    @Test func pendingWhileOpen() {
        #expect(AccountInsights.outcome(of: counted(1, 0, ended: false), optionId: "a", at: now) == .pending)
    }

    @Test func readsWonLostAndTiedFromTheCounts() {
        #expect(AccountInsights.outcome(of: counted(3, 1), optionId: "a", at: now) == .won)
        #expect(AccountInsights.outcome(of: counted(3, 1), optionId: "b", at: now) == .lost)
        #expect(AccountInsights.outcome(of: counted(2, 2), optionId: "b", at: now) == .tied)
    }

    @Test func unknownWhenTheCountsAreWithheld() {
        #expect(AccountInsights.outcome(of: counted(nil, nil), optionId: "a", at: now) == .unknown)
    }

    @Test func choiceIsThePickedOptionsText() {
        #expect(AccountInsights.choice(of: poll(myOptionId: "b")) == "B")
        #expect(AccountInsights.choice(of: poll(myOptionId: "gone")) == "")
    }
}

@Suite("Cursor")
struct CursorTests {
    struct Item: Identifiable, Equatable, Sendable { let id: Int }

    @Test func mergeDropsDuplicates() {
        #expect(mergeById([Item(id: 1), Item(id: 2)], [Item(id: 2), Item(id: 3), Item(id: 3)]) == [Item(id: 1), Item(id: 2), Item(id: 3)])
    }

    @Test func pageSizeIsClamped() {
        #expect(clampedPageSize(0) == 1)
        #expect(clampedPageSize(500) == 50)
    }

    @Test func collectStopsAtLastPageOrCap() async throws {
        let pages = ["": CursorPage(items: [1, 2], nextCursor: "2"), "2": CursorPage(items: [3], nextCursor: nil)]
        let all = try await collectPages(maxPages: 10) { pages[$0 ?? ""]! }
        #expect(all.page.items == [1, 2, 3])
        #expect(all.page.nextCursor == nil)
        let capped = try await collectPages(maxPages: 1) { pages[$0 ?? ""]! }
        #expect(capped.page.nextCursor == "2")
    }
}

@Suite("Avatars")
struct AvatarTests {
    // Expected values computed with vomatt-web's defaultBotFor()
    @Test func defaultKindMatchesTheWeb() {
        #expect(Avatars.defaultKind(for: "alice") == "banyan")
        #expect(Avatars.defaultKind(for: "chinssiang") == "pangolin")
        #expect(Avatars.defaultKind(for: "Bob_42") == "tofu")
        #expect(Avatars.defaultKind(for: "小明") == "boba")
    }

    @Test func parseAcceptsOnlyKnownBots() {
        #expect(Avatars.parse("bot:boba") == "boba")
        #expect(Avatars.parse("bot:nope") == nil)
        #expect(Avatars.parse("https://example.com/a.png") == nil)
        #expect(Avatars.resolve(username: "alice", avatarUrl: "https://x/y.png") == "banyan")
    }

    @Test func botNoneIsAPlainIconNotABot() {
        #expect(Avatars.isNone("bot:none"))
        #expect(!Avatars.isNone("bot:boba"))
        #expect(!Avatars.isNone(nil))
        #expect(Avatars.parse("bot:none") == nil)
    }

    @Test func castHas48WithTints() {
        #expect(Avatars.kinds.count == 48)
        #expect(Avatars.kinds.allSatisfy { Avatars.tints[$0] != nil })
    }
}

@Suite("Poll form")
struct PollFormTests {
    @Test func requiresTitleOptionsAndAFutureEnd() {
        let form = PollForm(title: " ", options: ["A", ""], endTime: hours(-1))
        let errors = form.errors(now: now)
        #expect(errors[.title] == "pollCreator.errors.titleRequired")
        #expect(errors[.option(1)] == "pollCreator.errors.optionRequired")
        #expect(errors[.endTime] == "pollCreator.errors.endBeforeStart")
    }

    @Test func inviteOnlyNeedsInvitees() {
        var form = PollForm(title: "Q", options: ["A", "B"], endTime: hours(5), audience: .inviteOnly)
        #expect(form.errors(now: now)[.invitees] == "pollCreator.errors.inviteesRequired")
        form.invitees = InviteeSelection(emails: ["a@b.co"])
        #expect(form.errors(now: now).isEmpty)
    }

    @Test func inputTrimsAndDropsInviteesForOtherAudiences() {
        var form = PollForm(title: " Q ", description: "  ", options: [" A", "B "], endTime: hours(5), audience: .public,
                            invitees: InviteeSelection(emails: ["a@b.co"]))
        var input = form.input(now: now)
        #expect(input.title == "Q")
        #expect(input.description == nil)
        #expect(input.options == ["A", "B"])
        #expect(input.invitees == nil)
        #expect(input.startTime == now)
        form.audience = .inviteOnly
        input = form.input(now: now)
        #expect(input.invitees?.emails == ["a@b.co"])
    }

    @Test func canAddOptionUntilTheLimit() {
        #expect(!PollForm(options: ["A", ""], endTime: nil).canAddOption)
        #expect(PollForm(options: ["A", "B"], endTime: nil).canAddOption)
        #expect(!PollForm(options: (0..<10).map(String.init), endTime: nil).canAddOption)
    }

    @Test func draftsRoundTrip() {
        let store = DraftStore(key: "test-drafts-\(UUID().uuidString)")
        let first = store.save(PollForm(title: "One", endTime: now))
        store.save(PollForm(title: "Two", endTime: now))
        store.save(PollForm(title: "One again", endTime: now), id: first.id)
        #expect(store.list().map(\.form.title) == ["One again", "Two"])
        #expect(store.delete(first.id).map(\.form.title) == ["Two"])
    }
}

@Suite("Username and email")
struct UsernameTests {
    @Test func usernameRule() {
        #expect(Username.isValid("alice_1"))
        #expect(!Username.isValid("ab"))
        #expect(!Username.isValid("Alice"))
        #expect(!Username.isValid("explore"))
        #expect(Username.isOwn("Alice", me: "alice"))
    }

    @Test func emailRule() {
        #expect(Email.isValid(" Me@Example.com "))
        #expect(Email.normalize(" Me@Example.com ") == "me@example.com")
        #expect(!Email.isValid("me@example"))
        #expect(!Email.isValid("@example.com"))
        #expect(!Email.isValid("a b@example.com"))
    }
}

@Suite("Block list")
struct BlockListTests {
    @Test func blocksCaseInsensitivelyAndUnblocks() {
        let list = BlockList(key: "test-blocks-\(UUID().uuidString)")
        #expect(!list.contains("Alice"))
        #expect(list.block("Alice") == ["alice"])
        list.block("bob")
        #expect(list.contains("ALICE"))
        #expect(!list.contains(nil))
        #expect(list.unblock("alice") == ["bob"])
        #expect(!list.contains("alice"))
    }
}

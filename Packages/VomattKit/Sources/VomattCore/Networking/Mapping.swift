import Foundation
import VomattAPI

// The generated types mark almost every field optional; these turn them into the
// domain models the app uses, failing like the web's zod parse when a field the
// UI depends on is missing. A contract change shows up here as a compile error.

typealias Schemas = Components.Schemas

func required<T>(_ value: T?, _ field: StaticString) throws -> T {
    guard let value else {
        throw APIError(.decoding, message: "Missing \(field) in the API response")
    }
    return value
}

extension Poll {
    init(_ dto: Schemas.VoteResponse) throws {
        self.init(
            id: try required(dto.id, "VoteResponse.id"),
            title: try required(dto.title, "VoteResponse.title"),
            description: dto.description,
            active: dto.active ?? true,
            votingActive: dto.votingActive ?? true,
            voterVisibility: dto.voterVisibility.map(VoterVisibility.init),
            audience: dto.audience.map(Audience.init),
            creatorId: try required(dto.creatorId, "VoteResponse.creatorId"),
            creatorUsername: try required(dto.creatorUsername, "VoteResponse.creatorUsername"),
            creatorAvatarUrl: dto.creatorAvatarUrl,
            createdAt: dto.createdAt ?? dto.startTime ?? .now,
            startTime: try required(dto.startTime, "VoteResponse.startTime"),
            endTime: dto.endTime,
            deadline: dto.deadline,
            inviteeCount: dto.inviteeCount.map(Int.init),
            deletable: dto.deletable,
            participantCount: dto.participantCount.map(Int.init),
            commentCount: dto.commentCount.map(Int.init),
            myOptionId: dto.myOptionId,
            myBallotAnonymous: dto.myBallotAnonymous,
            unread: dto.unread,
            options: try (dto.options ?? []).map(PollOption.init).sorted { $0.displayOrder < $1.displayOrder },
            tags: try (dto.tags ?? []).map(Tag.init)
        )
    }
}

extension PollOption {
    init(_ dto: Schemas.VoteOptionResponse) throws {
        self.init(
            id: try required(dto.id, "VoteOptionResponse.id"),
            text: dto.text ?? "",
            displayOrder: dto.displayOrder.map(Int.init) ?? 0,
            votes: dto.votes.map(Int.init)
        )
    }
}

extension Tag {
    init(_ dto: Schemas.TagDto) throws {
        self.init(
            id: try required(dto.id, "TagDto.id"),
            name: dto.name ?? "",
            slug: try required(dto.slug, "TagDto.slug"),
            usageCount: dto.usageCount.map(Int.init)
        )
    }
}

extension Audience {
    init(_ value: Schemas.VoteResponse.AudiencePayload) {
        switch value {
        case ._public: self = .public
        case .unlisted: self = .unlisted
        case .inviteOnly: self = .inviteOnly
        }
    }

    var request: Schemas.CreateVoteRequest.AudiencePayload {
        switch self {
        case .public: ._public
        case .unlisted: .unlisted
        case .inviteOnly: .inviteOnly
        }
    }
}

extension VoterVisibility {
    init(_ value: Schemas.VoteResponse.VoterVisibilityPayload) {
        switch value {
        case .nobody: self = .nobody
        case .owner: self = .owner
        case .signedIn: self = .signedIn
        }
    }

    var request: Schemas.CreateVoteRequest.VoterVisibilityPayload {
        switch self {
        case .nobody: .nobody
        case .owner: .owner
        case .signedIn: .signedIn
        }
    }
}

extension PollInput {
    var request: Schemas.CreateVoteRequest {
        let inviteOnly = audience == .inviteOnly
        return Schemas.CreateVoteRequest(
            allowMultipleChoices: false,
            anonymous: voterVisibility == .nobody,
            audience: audience?.request,
            description: description,
            endTime: endTime,
            // Other Audiences send no lists: the API rejects them, and switching away removes the Invitees
            inviteListIds: inviteOnly ? invitees?.groupIds : nil,
            inviteeEmails: inviteOnly ? invitees?.emails : nil,
            inviteeIds: inviteOnly ? invitees?.userIds : nil,
            options: options.enumerated().map { index, text in
                Schemas.VoteOptionRequest(displayOrder: Int32(index), text: text)
            },
            startTime: startTime,
            title: title,
            voterVisibility: voterVisibility.request
        )
    }
}

extension PollResults {
    init(_ dto: Schemas.VoteResultResponse) throws {
        self.init(
            id: try required(dto.id, "VoteResultResponse.id"),
            totalParticipants: dto.totalParticipants.map(Int.init),
            options: try (dto.options ?? []).map { option in
                Option(
                    id: try required(option.id, "VoteOptionResultResponse.id"),
                    text: option.text ?? "",
                    voteCount: option.voteCount.map(Int.init) ?? 0
                )
            }
        )
    }
}

extension Voter {
    init(_ dto: Schemas.VoterResponse) throws {
        self.init(
            userId: try required(dto.userId, "VoterResponse.userId"),
            username: dto.username ?? "",
            avatarUrl: dto.avatarUrl,
            optionId: dto.optionId,
            votedAt: dto.votedAt
        )
    }
}

extension Invitee {
    init(_ dto: Schemas.InviteeResponse) {
        self.init(
            person: Person(userId: dto.userId, username: dto.username, avatarUrl: dto.avatarUrl, email: dto.email),
            hasBallot: dto.hasBallot ?? false,
            invitedAt: dto.invitedAt
        )
    }
}

extension Comment {
    init(_ dto: Schemas.CommentDto) throws {
        self.init(
            id: try required(dto.id, "CommentDto.id"),
            userId: dto.userId,
            author: dto.author,
            authorAvatarUrl: dto.authorAvatarUrl,
            text: dto.text,
            createdAt: dto.createdAt ?? .now,
            likeCount: dto.likeCount.map(Int.init) ?? 0,
            edited: dto.edited ?? false,
            likedByCurrentUser: dto.likedByCurrentUser ?? false,
            parentId: dto.parentId,
            replyCount: dto.replyCount.map(Int.init) ?? 0,
            deleted: dto.deleted ?? false
        )
    }
}

extension UserProfile {
    init(_ dto: Schemas.UserProfileResponse) throws {
        self.init(
            id: dto.id,
            username: try required(dto.username, "UserProfileResponse.username"),
            displayName: dto.displayName,
            bio: dto.bio,
            avatarUrl: dto.avatarUrl,
            joinedAt: dto.joinedAt,
            totalPolls: dto.totalPolls.map(Int.init) ?? 0,
            totalVotes: dto.totalVotes.map(Int.init) ?? 0,
            location: dto.location,
            points: dto.points.map(Int.init),
            membershipLevel: dto.membershipLevel,
            isFollowing: dto.isFollowing,
            isBlocked: dto.isBlocked
        )
    }
}

extension MyProfile {
    init(_ dto: Schemas.MyProfileResponse) throws {
        self.init(
            id: try required(dto.id, "MyProfileResponse.id"),
            username: try required(dto.username, "MyProfileResponse.username"),
            email: dto.email,
            displayName: dto.displayName,
            bio: dto.bio,
            avatarUrl: dto.avatarUrl,
            firstName: dto.firstName,
            lastName: dto.lastName,
            location: dto.location,
            birthday: dto.birthday,
            points: dto.points.map(Int.init) ?? 0,
            membershipLevel: dto.membershipLevel,
            joinedAt: dto.joinedAt,
            totalPolls: dto.totalPolls.map(Int.init) ?? 0,
            totalVotes: dto.totalVotes.map(Int.init) ?? 0,
            visibilitySettings: dto.visibilitySettings?.additionalProperties ?? [:],
            anonymousBallotByDefault: dto.anonymousBallotByDefault ?? false
        )
    }
}

extension UserSummary {
    init(_ dto: Schemas.UserDto) throws {
        self.init(
            id: try required(dto.id, "UserDto.id"),
            username: try required(dto.username, "UserDto.username"),
            displayName: dto.displayName,
            avatarUrl: dto.avatarUrl
        )
    }
}

extension PollOwner {
    init(_ dto: Schemas.VoteCreatorResponse) throws {
        self.init(username: try required(dto.username, "VoteCreatorResponse.username"), avatarUrl: dto.avatarUrl)
    }
}

extension UserGroup {
    init(_ dto: Schemas.InviteListResponse) throws {
        self.init(
            id: try required(dto.id, "InviteListResponse.id"),
            name: dto.name ?? "",
            memberCount: dto.memberCount.map(Int.init) ?? 0
        )
    }
}

extension GroupMember {
    init(_ dto: Schemas.InviteListMemberResponse) {
        self.init(
            person: Person(userId: dto.userId, username: dto.username, avatarUrl: dto.avatarUrl, email: dto.email),
            addedAt: dto.addedAt
        )
    }
}

extension AuthTokens {
    init(_ dto: Schemas.AuthResponse) throws {
        self.init(
            accessToken: try required(dto.token, "AuthResponse.token"),
            refreshToken: try required(dto.refreshToken, "AuthResponse.refreshToken")
        )
    }
}

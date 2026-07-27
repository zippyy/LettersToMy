import Foundation

public enum FamilyBranchKind: String, Codable, CaseIterable, Sendable {
    case parents
    case maternal
    case paternal
    case chosenFamily
    case custom

    public var title: String {
        switch self {
        case .parents: "Parents"
        case .maternal: "Maternal family"
        case .paternal: "Paternal family"
        case .chosenFamily: "Chosen family"
        case .custom: "Custom"
        }
    }
}

public struct FamilyBranch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: FamilyBranchKind
    public var parentBranchID: UUID?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: FamilyBranchKind,
        parentBranchID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.parentBranchID = parentBranchID
    }
}

public struct ArchiveFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var branchID: UUID
    public var parentFolderID: UUID?
    public var name: String

    public init(
        id: UUID = UUID(),
        branchID: UUID,
        parentFolderID: UUID? = nil,
        name: String
    ) {
        self.id = id
        self.branchID = branchID
        self.parentFolderID = parentFolderID
        self.name = name
    }
}

public enum CollaborationRole: String, Codable, CaseIterable, Sendable {
    case owner
    case parentAdmin
    case organizer
    case contributor
    case viewer
    case recipient

    public var title: String {
        switch self {
        case .owner: "Owner"
        case .parentAdmin: "Parent / Admin"
        case .organizer: "Family Organizer"
        case .contributor: "Contributor"
        case .viewer: "Viewer"
        case .recipient: "Recipient"
        }
    }

    public var defaultPermissions: Set<CollaborationPermission> {
        switch self {
        case .owner:
            return Set(CollaborationPermission.allCases)
        case .parentAdmin:
            return Set(CollaborationPermission.allCases).subtracting([.transferOwnership])
        case .organizer:
            return [
                .viewContent,
                .viewSealedContent,
                .createContent,
                .editOwnContent,
                .editAnyContent,
                .deleteOwnContent,
                .deleteAnyContent,
                .manageFolders,
                .inviteContributors,
                .releaseLifeEventLetters
            ]
        case .contributor:
            return [
                .viewContent,
                .createContent,
                .editOwnContent,
                .deleteOwnContent
            ]
        case .viewer:
            return [.viewContent]
        case .recipient:
            return [.viewContent, .replyAsRecipient]
        }
    }
}

public enum CollaborationPermission: String, Codable, CaseIterable, Hashable, Sendable {
    case viewContent
    case viewSealedContent
    case createContent
    case editOwnContent
    case editAnyContent
    case deleteOwnContent
    case deleteAnyContent
    case manageFolders
    case inviteContributors
    case manageMembers
    case managePermissions
    case inviteRecipients
    case manageRecipients
    case releaseLifeEventLetters
    case exportArchive
    case replyAsRecipient
    case transferOwnership
}

public enum MembershipStatus: String, Codable, Sendable {
    case invited
    case active
    case suspended
    case removed
}

public struct CollaborationScope: Codable, Equatable, Sendable {
    public var archiveWide: Bool
    public var branchIDs: Set<UUID>
    public var folderIDs: Set<UUID>
    public var recipientIDs: Set<UUID>

    public init(
        archiveWide: Bool = false,
        branchIDs: Set<UUID> = [],
        folderIDs: Set<UUID> = [],
        recipientIDs: Set<UUID> = []
    ) {
        self.archiveWide = archiveWide
        self.branchIDs = branchIDs
        self.folderIDs = folderIDs
        self.recipientIDs = recipientIDs
    }

    public static let archive = CollaborationScope(archiveWide: true)

    public func permits(
        branchID: UUID?,
        folderID: UUID?,
        recipientID: UUID?
    ) -> Bool {
        if archiveWide { return true }

        let hasConstraint = !branchIDs.isEmpty || !folderIDs.isEmpty || !recipientIDs.isEmpty
        guard hasConstraint else { return false }

        let branchMatches = branchIDs.isEmpty || branchID.map(branchIDs.contains) == true
        let folderMatches = folderIDs.isEmpty || folderID.map(folderIDs.contains) == true
        let recipientMatches = recipientIDs.isEmpty || recipientID.map(recipientIDs.contains) == true

        return branchMatches && folderMatches && recipientMatches
    }
}

public struct ArchiveMember: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var displayName: String
    public var relationship: String
    public var role: CollaborationRole
    public var status: MembershipStatus
    public var scope: CollaborationScope
    public var grantedPermissions: Set<CollaborationPermission>
    public var deniedPermissions: Set<CollaborationPermission>
    public var canInviteOthers: Bool

    public init(
        id: UUID = UUID(),
        displayName: String,
        relationship: String,
        role: CollaborationRole,
        status: MembershipStatus = .active,
        scope: CollaborationScope,
        grantedPermissions: Set<CollaborationPermission> = [],
        deniedPermissions: Set<CollaborationPermission> = [],
        canInviteOthers: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.relationship = relationship
        self.role = role
        self.status = status
        self.scope = scope
        self.grantedPermissions = grantedPermissions
        self.deniedPermissions = deniedPermissions
        self.canInviteOthers = canInviteOthers
    }

    public var effectivePermissions: Set<CollaborationPermission> {
        role.defaultPermissions
            .union(grantedPermissions)
            .subtracting(deniedPermissions)
    }
}

public enum InvitationStatus: String, Codable, Sendable {
    case pending
    case delivered
    case sent
    case accepted
    case declined
    case expired
    case revoked
    case failed

    public var title: String {
        switch self {
        case .pending: "Pending"
        case .delivered: "Delivered"
        case .sent: "Sent"
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .expired: "Expired"
        case .revoked: "Revoked"
        case .failed: "Failed"
        }
    }
}

/// Lightweight metadata placed inside a shared partition so the accepting
/// participant can activate the correct local member record with the intended
/// role and scope. The inviter writes this before sharing; the invitee reads
/// it after accepting.
public struct ShareMemberActivation: Codable, Equatable, Sendable {
    public var invitationID: UUID
    public var intendedMemberID: UUID
    public var displayName: String
    public var role: CollaborationRole
    public var scope: CollaborationScope
    public var canInviteOthers: Bool

    public init(
        invitationID: UUID,
        intendedMemberID: UUID,
        displayName: String,
        role: CollaborationRole,
        scope: CollaborationScope,
        canInviteOthers: Bool = false
    ) {
        self.invitationID = invitationID
        self.intendedMemberID = intendedMemberID
        self.displayName = displayName
        self.role = role
        self.scope = scope
        self.canInviteOthers = canInviteOthers
    }
}

/// CloudKit participant identity that has been verified through share
/// acceptance rather than inferred from a user-provided email address.
public struct VerifiedParticipantIdentity: Codable, Equatable, Sendable {
    public var userRecordName: String
    public var participantType: String

    public init(userRecordName: String, participantType: String = "unknown") {
        self.userRecordName = userRecordName
        self.participantType = participantType
    }
}

public struct CollaborationInvitation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var inviteeDisplayName: String
    public var inviteeAddress: String
    public var relationship: String
    public var role: CollaborationRole
    public var scope: CollaborationScope
    public var status: InvitationStatus
    public var createdAt: Date
    public var expiresAt: Date?
    public var intendedRecipientID: UUID?

    public init(
        id: UUID = UUID(),
        inviteeDisplayName: String,
        inviteeAddress: String,
        relationship: String,
        role: CollaborationRole,
        scope: CollaborationScope,
        status: InvitationStatus = .pending,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        intendedRecipientID: UUID? = nil
    ) {
        self.id = id
        self.inviteeDisplayName = inviteeDisplayName
        self.inviteeAddress = inviteeAddress
        self.relationship = relationship
        self.role = role
        self.scope = scope
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.intendedRecipientID = intendedRecipientID
    }
}

public enum CollaborationAction: Sendable {
    case viewContent
    case createContent
    case editContent
    case deleteContent
    case manageFolders
    case inviteContributors
    case manageMembers
    case managePermissions
    case inviteRecipients
    case manageRecipients
    case releaseLifeEventLetter
    case exportArchive
    case replyAsRecipient
    case transferOwnership
}

public struct CollaborationContext: Sendable {
    public var branchID: UUID?
    public var folderID: UUID?
    public var recipientID: UUID?
    public var authorMemberID: UUID?
    public var isSealed: Bool
    public var isUnlocked: Bool

    public init(
        branchID: UUID? = nil,
        folderID: UUID? = nil,
        recipientID: UUID? = nil,
        authorMemberID: UUID? = nil,
        isSealed: Bool = false,
        isUnlocked: Bool = true
    ) {
        self.branchID = branchID
        self.folderID = folderID
        self.recipientID = recipientID
        self.authorMemberID = authorMemberID
        self.isSealed = isSealed
        self.isUnlocked = isUnlocked
    }
}

public enum CollaborationPolicy {
    public static func allows(
        _ member: ArchiveMember,
        action: CollaborationAction,
        context: CollaborationContext
    ) -> Bool {
        guard member.status == .active else { return false }
        guard member.scope.permits(
            branchID: context.branchID,
            folderID: context.folderID,
            recipientID: context.recipientID
        ) else {
            return false
        }

        let permissions = member.effectivePermissions
        let ownsContent = context.authorMemberID == member.id

        if member.role == .recipient {
            guard context.recipientID != nil, context.isUnlocked, !context.isSealed else {
                return false
            }
        }

        switch action {
        case .viewContent:
            guard permissions.contains(.viewContent) else { return false }
            return !context.isSealed || permissions.contains(.viewSealedContent)
        case .createContent:
            return permissions.contains(.createContent)
        case .editContent:
            return permissions.contains(.editAnyContent)
                || (ownsContent && permissions.contains(.editOwnContent))
        case .deleteContent:
            return permissions.contains(.deleteAnyContent)
                || (ownsContent && permissions.contains(.deleteOwnContent))
        case .manageFolders:
            return permissions.contains(.manageFolders)
        case .inviteContributors:
            return permissions.contains(.inviteContributors)
        case .manageMembers:
            return permissions.contains(.manageMembers)
        case .managePermissions:
            return permissions.contains(.managePermissions)
        case .inviteRecipients:
            return permissions.contains(.inviteRecipients)
        case .manageRecipients:
            return permissions.contains(.manageRecipients)
        case .releaseLifeEventLetter:
            return permissions.contains(.releaseLifeEventLetters)
        case .exportArchive:
            return permissions.contains(.exportArchive)
        case .replyAsRecipient:
            return member.role == .recipient && permissions.contains(.replyAsRecipient)
        case .transferOwnership:
            return permissions.contains(.transferOwnership)
        }
    }
}

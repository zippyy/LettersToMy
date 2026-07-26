import Foundation
import LettersToMyCore
import SwiftData

@Model
final class FamilyBranchRecord {
    var id: UUID = UUID()
    var name: String = ""
    var kindRawValue: String = FamilyBranchKind.custom.rawValue
    var parentBranchID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        name: String,
        kind: FamilyBranchKind,
        parentBranchID: UUID? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.kindRawValue = kind.rawValue
        self.parentBranchID = parentBranchID
        self.createdAt = .now
        self.updatedAt = .now
    }

    var kind: FamilyBranchKind {
        get { FamilyBranchKind(rawValue: kindRawValue) ?? .custom }
        set { kindRawValue = newValue.rawValue }
    }
}

@Model
final class ArchiveFolderRecord {
    var id: UUID = UUID()
    var branchID: UUID = UUID()
    var parentFolderID: UUID?
    var name: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        branchID: UUID,
        name: String,
        parentFolderID: UUID? = nil
    ) {
        self.id = UUID()
        self.branchID = branchID
        self.parentFolderID = parentFolderID
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
final class ArchiveMemberRecord {
    var id: UUID = UUID()
    var displayName: String = ""
    var relationship: String = ""
    var roleRawValue: String = CollaborationRole.viewer.rawValue
    var statusRawValue: String = MembershipStatus.invited.rawValue
    var scopeData: Data?
    var grantedPermissionsData: Data?
    var deniedPermissionsData: Data?
    var canInviteOthers: Bool = false
    var cloudKitParticipantRecordName: String?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        displayName: String,
        relationship: String,
        role: CollaborationRole,
        status: MembershipStatus = .invited,
        scope: CollaborationScope,
        grantedPermissions: Set<CollaborationPermission> = [],
        deniedPermissions: Set<CollaborationPermission> = [],
        canInviteOthers: Bool = false
    ) {
        self.id = UUID()
        self.displayName = displayName
        self.relationship = relationship
        self.roleRawValue = role.rawValue
        self.statusRawValue = status.rawValue
        self.scopeData = try? JSONEncoder().encode(scope)
        self.grantedPermissionsData = try? JSONEncoder().encode(grantedPermissions)
        self.deniedPermissionsData = try? JSONEncoder().encode(deniedPermissions)
        self.canInviteOthers = canInviteOthers
        self.createdAt = .now
        self.updatedAt = .now
    }

    var role: CollaborationRole {
        get { CollaborationRole(rawValue: roleRawValue) ?? .viewer }
        set { roleRawValue = newValue.rawValue }
    }

    var status: MembershipStatus {
        get { MembershipStatus(rawValue: statusRawValue) ?? .invited }
        set { statusRawValue = newValue.rawValue }
    }

    var scope: CollaborationScope {
        get {
            guard let scopeData,
                  let decoded = try? JSONDecoder().decode(CollaborationScope.self, from: scopeData) else {
                return CollaborationScope()
            }
            return decoded
        }
        set { scopeData = try? JSONEncoder().encode(newValue) }
    }

    var domainMember: ArchiveMember {
        ArchiveMember(
            id: id,
            displayName: displayName,
            relationship: relationship,
            role: role,
            status: status,
            scope: scope,
            grantedPermissions: decodePermissions(grantedPermissionsData),
            deniedPermissions: decodePermissions(deniedPermissionsData),
            canInviteOthers: canInviteOthers
        )
    }

    private func decodePermissions(_ data: Data?) -> Set<CollaborationPermission> {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(Set<CollaborationPermission>.self, from: data)) ?? []
    }
}

@Model
final class CollaborationInvitationRecord {
    var id: UUID = UUID()
    var inviteeDisplayName: String = ""
    var inviteeAddress: String = ""
    var relationship: String = ""
    var roleRawValue: String = CollaborationRole.contributor.rawValue
    var scopeData: Data?
    var statusRawValue: String = InvitationStatus.pending.rawValue
    var createdAt: Date = Date.now
    var expiresAt: Date?
    var intendedRecipientID: UUID?
    var canInviteOthers: Bool = false

    init(
        inviteeDisplayName: String,
        inviteeAddress: String,
        relationship: String,
        role: CollaborationRole,
        scope: CollaborationScope,
        intendedRecipientID: UUID? = nil,
        canInviteOthers: Bool = false
    ) {
        self.id = UUID()
        self.inviteeDisplayName = inviteeDisplayName
        self.inviteeAddress = inviteeAddress
        self.relationship = relationship
        self.roleRawValue = role.rawValue
        self.scopeData = try? JSONEncoder().encode(scope)
        self.statusRawValue = InvitationStatus.pending.rawValue
        self.createdAt = .now
        self.intendedRecipientID = intendedRecipientID
        self.canInviteOthers = canInviteOthers
    }

    var role: CollaborationRole {
        get { CollaborationRole(rawValue: roleRawValue) ?? .contributor }
        set { roleRawValue = newValue.rawValue }
    }

    var status: InvitationStatus {
        get { InvitationStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    var scope: CollaborationScope {
        get {
            guard let scopeData,
                  let decoded = try? JSONDecoder().decode(CollaborationScope.self, from: scopeData) else {
                return CollaborationScope()
            }
            return decoded
        }
        set { scopeData = try? JSONEncoder().encode(newValue) }
    }
}

import CoreData
import Foundation
import LettersToMyCore

@objc(FamilyBranchRecord)
final class FamilyBranchRecord: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var kindRawValue: String
    @NSManaged var parentBranchID: UUID?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var partition: SharePartitionRecord?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        name = ""
        kindRawValue = FamilyBranchKind.custom.rawValue
        createdAt = .now
        updatedAt = .now
    }

    var kind: FamilyBranchKind {
        get { FamilyBranchKind(rawValue: kindRawValue) ?? .custom }
        set { kindRawValue = newValue.rawValue }
    }
}

@objc(ArchiveFolderRecord)
final class ArchiveFolderRecord: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var branchID: UUID
    @NSManaged var parentFolderID: UUID?
    @NSManaged var name: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var partition: SharePartitionRecord?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        branchID = UUID()
        name = ""
        createdAt = .now
        updatedAt = .now
    }
}

@objc(ArchiveMemberRecord)
final class ArchiveMemberRecord: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var displayName: String
    @NSManaged var relationship: String
    @NSManaged var roleRawValue: String
    @NSManaged var statusRawValue: String
    @NSManaged var scopeData: Data?
    @NSManaged var grantedPermissionsData: Data?
    @NSManaged var deniedPermissionsData: Data?
    @NSManaged var canInviteOthers: Bool
    @NSManaged var cloudKitParticipantRecordName: String?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var partition: SharePartitionRecord?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        displayName = ""
        relationship = ""
        roleRawValue = CollaborationRole.viewer.rawValue
        statusRawValue = MembershipStatus.invited.rawValue
        canInviteOthers = false
        createdAt = .now
        updatedAt = .now
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

    var grantedPermissions: Set<CollaborationPermission> {
        get { decodePermissions(grantedPermissionsData) }
        set { grantedPermissionsData = try? JSONEncoder().encode(newValue) }
    }

    var deniedPermissions: Set<CollaborationPermission> {
        get { decodePermissions(deniedPermissionsData) }
        set { deniedPermissionsData = try? JSONEncoder().encode(newValue) }
    }

    var domainMember: ArchiveMember {
        ArchiveMember(
            id: id,
            displayName: displayName,
            relationship: relationship,
            role: role,
            status: status,
            scope: scope,
            grantedPermissions: grantedPermissions,
            deniedPermissions: deniedPermissions,
            canInviteOthers: canInviteOthers
        )
    }

    private func decodePermissions(_ data: Data?) -> Set<CollaborationPermission> {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(Set<CollaborationPermission>.self, from: data)) ?? []
    }
}

@objc(CollaborationInvitationRecord)
final class CollaborationInvitationRecord: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var inviteeDisplayName: String
    @NSManaged var inviteeAddress: String
    @NSManaged var relationship: String
    @NSManaged var roleRawValue: String
    @NSManaged var scopeData: Data?
    @NSManaged var statusRawValue: String
    @NSManaged var createdAt: Date
    @NSManaged var expiresAt: Date?
    @NSManaged var intendedRecipientID: UUID?
    @NSManaged var canInviteOthers: Bool
    @NSManaged var partition: SharePartitionRecord?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        inviteeDisplayName = ""
        inviteeAddress = ""
        relationship = ""
        roleRawValue = CollaborationRole.contributor.rawValue
        statusRawValue = InvitationStatus.pending.rawValue
        createdAt = .now
        canInviteOthers = false
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

enum SharePartitionKind: String, CaseIterable {
    case archiveAdministration
    case branch
    case folder
    case recipientInbox

    var title: String {
        switch self {
        case .archiveAdministration: "Archive Administration"
        case .branch: "Family Side"
        case .folder: "Folder"
        case .recipientInbox: "Recipient Inbox"
        }
    }
}

@objc(SharePartitionRecord)
final class SharePartitionRecord: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var kindRawValue: String
    @NSManaged var scopeID: UUID?
    @NSManaged var displayName: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var children: NSSet?
    @NSManaged var letters: NSSet?
    @NSManaged var branches: NSSet?
    @NSManaged var folders: NSSet?
    @NSManaged var members: NSSet?
    @NSManaged var invitations: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        kindRawValue = SharePartitionKind.archiveAdministration.rawValue
        displayName = "Family Archive"
        createdAt = .now
        updatedAt = .now
    }

    var kind: SharePartitionKind {
        get { SharePartitionKind(rawValue: kindRawValue) ?? .archiveAdministration }
        set { kindRawValue = newValue.rawValue }
    }

    var cloudShareItem: CloudKitShareItem {
        CloudKitShareItem(
            partitionURI: objectID.uriRepresentation(),
            title: displayName
        )
    }
}

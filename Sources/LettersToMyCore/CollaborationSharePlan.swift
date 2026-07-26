import Foundation

public enum CollaborationSharePermission: String, Codable, Sendable {
    case readOnly
    case readWrite
}

public enum CollaborationSharePartition: Codable, Equatable, Hashable, Sendable {
    case archiveAdministration
    case branch(UUID)
    case folder(UUID)
    case recipientInbox(UUID)
}

public struct CollaborationShareGrant: Codable, Equatable, Sendable {
    public var partition: CollaborationSharePartition
    public var permission: CollaborationSharePermission
    public var canInviteOthers: Bool

    public init(
        partition: CollaborationSharePartition,
        permission: CollaborationSharePermission,
        canInviteOthers: Bool = false
    ) {
        self.partition = partition
        self.permission = permission
        self.canInviteOthers = canInviteOthers
    }
}

public enum CollaborationSharePlanner {
    public static func grants(
        for member: ArchiveMember,
        availableBranchIDs: Set<UUID> = [],
        availableRecipientIDs: Set<UUID> = []
    ) -> [CollaborationShareGrant] {
        guard member.status == .active || member.status == .invited else {
            return []
        }

        switch member.role {
        case .owner:
            // The owner already controls the private database and owns each share.
            return []

        case .parentAdmin:
            var grants = [
                CollaborationShareGrant(
                    partition: .archiveAdministration,
                    permission: .readWrite,
                    canInviteOthers: member.canInviteOthers
                )
            ]
            grants += availableBranchIDs.map {
                CollaborationShareGrant(
                    partition: .branch($0),
                    permission: .readWrite,
                    canInviteOthers: member.canInviteOthers
                )
            }
            grants += availableRecipientIDs.map {
                CollaborationShareGrant(
                    partition: .recipientInbox($0),
                    permission: .readWrite,
                    canInviteOthers: member.canInviteOthers
                )
            }
            return grants.sorted(by: stablePartitionOrder)

        case .organizer, .contributor:
            let folderGrants = member.scope.folderIDs.map {
                CollaborationShareGrant(
                    partition: .folder($0),
                    permission: .readWrite,
                    canInviteOthers: member.canInviteOthers
                )
            }
            if !folderGrants.isEmpty {
                return folderGrants.sorted(by: stablePartitionOrder)
            }
            return member.scope.branchIDs.map {
                CollaborationShareGrant(
                    partition: .branch($0),
                    permission: .readWrite,
                    canInviteOthers: member.canInviteOthers
                )
            }
            .sorted(by: stablePartitionOrder)

        case .viewer:
            let folderGrants = member.scope.folderIDs.map {
                CollaborationShareGrant(partition: .folder($0), permission: .readOnly)
            }
            if !folderGrants.isEmpty {
                return folderGrants.sorted(by: stablePartitionOrder)
            }
            return member.scope.branchIDs.map {
                CollaborationShareGrant(partition: .branch($0), permission: .readOnly)
            }
            .sorted(by: stablePartitionOrder)

        case .recipient:
            return member.scope.recipientIDs.map {
                CollaborationShareGrant(partition: .recipientInbox($0), permission: .readOnly)
            }
            .sorted(by: stablePartitionOrder)
        }
    }

    private static func stablePartitionOrder(
        _ lhs: CollaborationShareGrant,
        _ rhs: CollaborationShareGrant
    ) -> Bool {
        partitionSortKey(lhs.partition) < partitionSortKey(rhs.partition)
    }

    private static func partitionSortKey(_ partition: CollaborationSharePartition) -> String {
        switch partition {
        case .archiveAdministration:
            return "0-archive"
        case .branch(let id):
            return "1-branch-\(id.uuidString)"
        case .folder(let id):
            return "2-folder-\(id.uuidString)"
        case .recipientInbox(let id):
            return "3-recipient-\(id.uuidString)"
        }
    }
}

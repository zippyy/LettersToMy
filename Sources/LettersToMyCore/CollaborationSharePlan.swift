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
            // Archive-wide access grants the administration share plus every
            // branch and recipient share. A NARROWER scope (branch or folder)
            // only grants that scope's shares — otherwise a branch-scoped
            // parent/admin would receive every branch and recipient inbox in
            // the archive, over-sharing sealed content.
            if member.scope.archiveWide {
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
            }
            // Scoped parent/admin: fall through to the scoped content grants
            // so the scope is honored.
            return scopedContentGrants(for: member)

        case .organizer, .contributor:
            return scopedContentGrants(for: member, permission: .readWrite)

        case .viewer:
            return scopedContentGrants(for: member, permission: .readOnly)

        case .recipient:
            return member.scope.recipientIDs.map {
                CollaborationShareGrant(partition: .recipientInbox($0), permission: .readOnly)
            }
            .sorted(by: stablePartitionOrder)
        }
    }

    /// Content-scoped grants for a member: folders first (narrowest), then
    /// branches. Used by scoped parent/admins, organizers, contributors,
    /// and viewers so every role honors the same scope rules.
    private static func scopedContentGrants(
        for member: ArchiveMember,
        permission: CollaborationSharePermission = .readWrite
    ) -> [CollaborationShareGrant] {
        let folderGrants = member.scope.folderIDs.map {
            CollaborationShareGrant(
                partition: .folder($0),
                permission: permission,
                canInviteOthers: member.canInviteOthers
            )
        }
        if !folderGrants.isEmpty {
            return folderGrants.sorted(by: stablePartitionOrder)
        }
        return member.scope.branchIDs.map {
            CollaborationShareGrant(
                partition: .branch($0),
                permission: permission,
                canInviteOthers: member.canInviteOthers
            )
        }
        .sorted(by: stablePartitionOrder)
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

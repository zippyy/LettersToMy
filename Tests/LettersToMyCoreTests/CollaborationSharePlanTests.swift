import Foundation
import Testing
@testable import LettersToMyCore

struct CollaborationSharePlanTests {
    @Test func parentAdminReceivesAdministrativeBranchAndRecipientShares() {
        let maternal = UUID()
        let paternal = UUID()
        let child = UUID()
        let member = ArchiveMember(
            displayName: "Spouse",
            relationship: "Parent",
            role: .parentAdmin,
            scope: .archive,
            canInviteOthers: true
        )

        let grants = CollaborationSharePlanner.grants(
            for: member,
            availableBranchIDs: [maternal, paternal],
            availableRecipientIDs: [child]
        )

        #expect(grants.contains(CollaborationShareGrant(
            partition: .archiveAdministration,
            permission: .readWrite,
            canInviteOthers: true
        )))
        #expect(grants.contains(CollaborationShareGrant(
            partition: .branch(maternal),
            permission: .readWrite,
            canInviteOthers: true
        )))
        #expect(grants.contains(CollaborationShareGrant(
            partition: .recipientInbox(child),
            permission: .readWrite,
            canInviteOthers: true
        )))
    }

    @Test func contributorReceivesOnlyAssignedBranchAsReadWrite() {
        let maternal = UUID()
        let member = ArchiveMember(
            displayName: "Grandma",
            relationship: "Maternal grandmother",
            role: .contributor,
            scope: CollaborationScope(branchIDs: [maternal])
        )

        #expect(CollaborationSharePlanner.grants(for: member) == [
            CollaborationShareGrant(partition: .branch(maternal), permission: .readWrite)
        ])
    }

    @Test func folderScopeIsNarrowerThanBranchScope() {
        let branch = UUID()
        let folder = UUID()
        let member = ArchiveMember(
            displayName: "Cousin",
            relationship: "Cousin",
            role: .contributor,
            scope: CollaborationScope(branchIDs: [branch], folderIDs: [folder])
        )

        #expect(CollaborationSharePlanner.grants(for: member) == [
            CollaborationShareGrant(partition: .folder(folder), permission: .readWrite)
        ])
    }

    @Test func viewerReceivesReadOnlyShare() {
        let branch = UUID()
        let member = ArchiveMember(
            displayName: "Family friend",
            relationship: "Family friend",
            role: .viewer,
            scope: CollaborationScope(branchIDs: [branch])
        )

        #expect(CollaborationSharePlanner.grants(for: member) == [
            CollaborationShareGrant(partition: .branch(branch), permission: .readOnly)
        ])
    }

    @Test func recipientReceivesOnlyTheirReadOnlyInbox() {
        let child = UUID()
        let member = ArchiveMember(
            displayName: "Daughter",
            relationship: "Recipient",
            role: .recipient,
            scope: CollaborationScope(recipientIDs: [child])
        )

        #expect(CollaborationSharePlanner.grants(for: member) == [
            CollaborationShareGrant(partition: .recipientInbox(child), permission: .readOnly)
        ])
    }

    @Test func removedMemberReceivesNoShares() {
        let member = ArchiveMember(
            displayName: "Former collaborator",
            relationship: "Relative",
            role: .contributor,
            status: .removed,
            scope: CollaborationScope(branchIDs: [UUID()])
        )

        #expect(CollaborationSharePlanner.grants(for: member).isEmpty)
    }
}

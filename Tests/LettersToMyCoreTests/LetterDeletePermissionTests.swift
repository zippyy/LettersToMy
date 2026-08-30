import Foundation
import Testing
@testable import LettersToMyCore

/// Focused regression matrix for the deleteContent permission path that the
/// Letter deletion flow relies on. Every case maps to a UI rule: the Delete
/// button is only shown when canPerform(.deleteContent) allows it, so these
/// tests pin exactly which members may delete what.
struct LetterDeletePermissionTests {
    private let maternalBranchID = UUID()
    private let paternalBranchID = UUID()
    private let childID = UUID()

    private func sealedContext(
        branchID: UUID? = nil,
        folderID: UUID? = nil,
        recipientID: UUID? = nil,
        authorMemberID: UUID? = nil
    ) -> CollaborationContext {
        CollaborationContext(
            branchID: branchID,
            folderID: folderID,
            recipientID: recipientID,
            authorMemberID: authorMemberID,
            isSealed: true,
            isUnlocked: false
        )
    }

    @Test func ownerCanDeleteAnyContentIncludingSealed() {
        let owner = ArchiveMember(displayName: "Owner", relationship: "Owner", role: .owner, scope: .archive)
        let context = sealedContext(branchID: paternalBranchID, authorMemberID: UUID())

        #expect(CollaborationPolicy.allows(owner, action: .deleteContent, context: context))
    }

    @Test func parentAdminCanDeleteAnyContent() {
        let admin = ArchiveMember(displayName: "Parent", relationship: "Parent", role: .parentAdmin, scope: .archive)
        let context = sealedContext(branchID: maternalBranchID, authorMemberID: UUID())

        #expect(CollaborationPolicy.allows(admin, action: .deleteContent, context: context))
    }

    @Test func contributorCanDeleteOwnContentButNotAnotherMembers() {
        let contributor = ArchiveMember(
            displayName: "Grandpa",
            relationship: "Grandfather",
            role: .contributor,
            scope: CollaborationScope(branchIDs: [paternalBranchID])
        )

        let own = sealedContext(branchID: paternalBranchID, authorMemberID: contributor.id)
        let others = sealedContext(branchID: paternalBranchID, authorMemberID: UUID())

        #expect(CollaborationPolicy.allows(contributor, action: .deleteContent, context: own))
        #expect(!CollaborationPolicy.allows(contributor, action: .deleteContent, context: others))
    }

    @Test func contributorDeleteIsScopedToAssignedBranch() {
        let contributor = ArchiveMember(
            displayName: "Grandma",
            relationship: "Grandmother",
            role: .contributor,
            scope: CollaborationScope(branchIDs: [maternalBranchID])
        )

        let inScope = sealedContext(branchID: maternalBranchID, authorMemberID: contributor.id)
        let outOfScope = sealedContext(branchID: paternalBranchID, authorMemberID: contributor.id)

        #expect(CollaborationPolicy.allows(contributor, action: .deleteContent, context: inScope))
        #expect(!CollaborationPolicy.allows(contributor, action: .deleteContent, context: outOfScope))
    }

    @Test func viewerCannotDeleteContent() {
        let viewer = ArchiveMember(
            displayName: "Aunt",
            relationship: "Aunt",
            role: .viewer,
            scope: CollaborationScope(branchIDs: [maternalBranchID])
        )
        let context = sealedContext(branchID: maternalBranchID, authorMemberID: viewer.id)

        #expect(!CollaborationPolicy.allows(viewer, action: .deleteContent, context: context))
    }

    @Test func recipientCannotDeleteContentEvenWhenUnlocked() {
        let recipient = ArchiveMember(
            displayName: "Daughter",
            relationship: "Recipient",
            role: .recipient,
            scope: CollaborationScope(recipientIDs: [childID])
        )
        let unlocked = CollaborationContext(
            recipientID: childID,
            authorMemberID: recipient.id,
            isSealed: false,
            isUnlocked: true
        )

        #expect(!CollaborationPolicy.allows(recipient, action: .deleteContent, context: unlocked))
    }

    @Test func explicitDenyOfDeleteAnyBlocksDeletingOthersContent() {
        let organizer = ArchiveMember(
            displayName: "Uncle",
            relationship: "Uncle",
            role: .organizer,
            scope: CollaborationScope(branchIDs: [paternalBranchID]),
            deniedPermissions: [.deleteAnyContent]
        )
        let context = sealedContext(branchID: paternalBranchID, authorMemberID: UUID())

        #expect(!CollaborationPolicy.allows(organizer, action: .deleteContent, context: context))
    }

    @Test func inactiveMembersCannotDelete() {
        let roles: [(CollaborationRole, MembershipStatus)] = [
            (.parentAdmin, .invited),
            (.parentAdmin, .suspended),
            (.parentAdmin, .removed),
        ]
        for (role, status) in roles {
            let member = ArchiveMember(
                displayName: "Member",
                relationship: "Member",
                role: role,
                status: status,
                scope: .archive
            )
            let context = sealedContext(branchID: maternalBranchID)
            #expect(!CollaborationPolicy.allows(member, action: .deleteContent, context: context))
        }
    }

    @Test func deleteOfOwnDraftAllowedForContributor() {
        // Drafts are not sealed and not unlocked; the context must reflect
        // that (isSealed false, isUnlocked false) so deletion is permitted
        // for a contributor who authored the draft.
        let contributor = ArchiveMember(
            displayName: "Cousin",
            relationship: "Cousin",
            role: .contributor,
            scope: CollaborationScope(branchIDs: [maternalBranchID])
        )
        let draft = CollaborationContext(
            branchID: maternalBranchID,
            authorMemberID: contributor.id,
            isSealed: false,
            isUnlocked: false
        )

        #expect(CollaborationPolicy.allows(contributor, action: .deleteContent, context: draft))
    }
}

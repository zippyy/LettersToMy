import Foundation
import Testing
@testable import LettersToMyCore

struct CollaborationPolicyTests {
    private let maternalBranchID = UUID()
    private let paternalBranchID = UUID()
    private let childID = UUID()

    @Test func parentAdminCanManageArchiveButCannotTransferOwnership() {
        let member = ArchiveMember(
            displayName: "Parent",
            relationship: "Parent",
            role: .parentAdmin,
            scope: .archive
        )
        let context = CollaborationContext(branchID: maternalBranchID, recipientID: childID)

        #expect(CollaborationPolicy.allows(member, action: .manageMembers, context: context))
        #expect(CollaborationPolicy.allows(member, action: .viewContent, context: context))
        #expect(!CollaborationPolicy.allows(member, action: .transferOwnership, context: context))
    }

    @Test func grandparentContributorIsLimitedToAssignedFamilyBranch() {
        let member = ArchiveMember(
            displayName: "Grandma",
            relationship: "Maternal grandmother",
            role: .contributor,
            scope: CollaborationScope(branchIDs: [maternalBranchID])
        )

        let maternalContext = CollaborationContext(branchID: maternalBranchID, recipientID: childID)
        let paternalContext = CollaborationContext(branchID: paternalBranchID, recipientID: childID)

        #expect(CollaborationPolicy.allows(member, action: .createContent, context: maternalContext))
        #expect(!CollaborationPolicy.allows(member, action: .createContent, context: paternalContext))
    }

    @Test func contributorCanEditOwnContentButNotAnotherMembersContent() {
        let contributor = ArchiveMember(
            displayName: "Grandpa",
            relationship: "Grandfather",
            role: .contributor,
            scope: CollaborationScope(branchIDs: [paternalBranchID])
        )

        let ownContext = CollaborationContext(
            branchID: paternalBranchID,
            recipientID: childID,
            authorMemberID: contributor.id
        )
        let otherContext = CollaborationContext(
            branchID: paternalBranchID,
            recipientID: childID,
            authorMemberID: UUID()
        )

        #expect(CollaborationPolicy.allows(contributor, action: .editContent, context: ownContext))
        #expect(!CollaborationPolicy.allows(contributor, action: .editContent, context: otherContext))
    }

    @Test func ordinaryViewerCannotSeeSealedContent() {
        let viewer = ArchiveMember(
            displayName: "Aunt",
            relationship: "Aunt",
            role: .viewer,
            scope: CollaborationScope(branchIDs: [maternalBranchID])
        )
        let context = CollaborationContext(
            branchID: maternalBranchID,
            recipientID: childID,
            isSealed: true,
            isUnlocked: false
        )

        #expect(!CollaborationPolicy.allows(viewer, action: .viewContent, context: context))
    }

    @Test func recipientOnlyReadsTheirOwnUnlockedContent() {
        let recipient = ArchiveMember(
            displayName: "Daughter",
            relationship: "Recipient",
            role: .recipient,
            scope: CollaborationScope(recipientIDs: [childID])
        )

        let unlocked = CollaborationContext(
            recipientID: childID,
            isSealed: false,
            isUnlocked: true
        )
        let locked = CollaborationContext(
            recipientID: childID,
            isSealed: true,
            isUnlocked: false
        )
        let anotherChild = CollaborationContext(
            recipientID: UUID(),
            isSealed: false,
            isUnlocked: true
        )

        #expect(CollaborationPolicy.allows(recipient, action: .viewContent, context: unlocked))
        #expect(CollaborationPolicy.allows(recipient, action: .replyAsRecipient, context: unlocked))
        #expect(!CollaborationPolicy.allows(recipient, action: .viewContent, context: locked))
        #expect(!CollaborationPolicy.allows(recipient, action: .viewContent, context: anotherChild))
    }

    @Test func explicitDenialOverridesRoleDefaults() {
        let organizer = ArchiveMember(
            displayName: "Family Organizer",
            relationship: "Uncle",
            role: .organizer,
            scope: CollaborationScope(branchIDs: [paternalBranchID]),
            deniedPermissions: [.deleteAnyContent]
        )
        let context = CollaborationContext(
            branchID: paternalBranchID,
            recipientID: childID,
            authorMemberID: UUID()
        )

        #expect(!CollaborationPolicy.allows(organizer, action: .deleteContent, context: context))
        #expect(CollaborationPolicy.allows(organizer, action: .manageFolders, context: context))
    }

    @Test func suspendedMemberCannotPerformAnyAction() {
        let member = ArchiveMember(
            displayName: "Suspended Member",
            relationship: "Family member",
            role: .contributor,
            status: .suspended,
            scope: .archive
        )
        let context = CollaborationContext(isSealed: false, isUnlocked: true)

        for action in CollaborationAction.allCases {
            #expect(!CollaborationPolicy.allows(member, action: action, context: context))
        }
    }

    @Test func removedMemberCannotPerformAnyAction() {
        let member = ArchiveMember(
            displayName: "Removed Member",
            relationship: "Former collaborator",
            role: .parentAdmin,
            status: .removed,
            scope: .archive
        )
        let context = CollaborationContext(isSealed: false, isUnlocked: true)

        for action in CollaborationAction.allCases {
            #expect(!CollaborationPolicy.allows(member, action: action, context: context))
        }
    }

    @Test func invitedMemberCannotPerformAnyActionBeforeAcceptance() {
        let member = ArchiveMember(
            displayName: "Pending Member",
            relationship: "Invitee",
            role: .parentAdmin,
            status: .invited,
            scope: .archive
        )
        let context = CollaborationContext(isSealed: false, isUnlocked: true)

        for action in CollaborationAction.allCases {
            #expect(!CollaborationPolicy.allows(member, action: action, context: context))
        }
    }

    @Test func sealedContentVisibleOnlyToRolesWithThePermission() {
        let context = CollaborationContext(isSealed: true, isUnlocked: false)
        let owner = ArchiveMember(displayName: "Owner", relationship: "Owner", role: .owner, scope: .archive)
        let admin = ArchiveMember(displayName: "Parent", relationship: "Parent", role: .parentAdmin, scope: .archive)
        let organizer = ArchiveMember(displayName: "Uncle", relationship: "Uncle", role: .organizer, scope: .archive)
        let contributor = ArchiveMember(displayName: "Cousin", relationship: "Cousin", role: .contributor, scope: .archive)
        let viewer = ArchiveMember(displayName: "Aunt", relationship: "Aunt", role: .viewer, scope: .archive)

        #expect(CollaborationPolicy.allows(owner, action: .viewSealedContent, context: context))
        #expect(CollaborationPolicy.allows(admin, action: .viewSealedContent, context: context))
        #expect(CollaborationPolicy.allows(organizer, action: .viewSealedContent, context: context))
        #expect(!CollaborationPolicy.allows(contributor, action: .viewSealedContent, context: context))
        #expect(!CollaborationPolicy.allows(viewer, action: .viewSealedContent, context: context))
    }
}

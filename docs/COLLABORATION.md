# Collaboration and Recipient Access

## Goals

LettersToMy supports three distinct kinds of access:

1. **Archive administration** for spouses, co-parents, and trusted guardians.
2. **Scoped contribution** for grandparents, relatives, and family friends.
3. **Recipient delivery** for the children or other people the letters are written to.

These are intentionally separate. A contributor should not automatically see every sealed letter, and a recipient should never receive the archive's master records before they unlock.

## Roles

| Role | Intended use | Default access |
| --- | --- | --- |
| Owner | Archive creator | Everything, including ownership transfer |
| Parent / Admin | Spouse, co-parent, guardian | Archive-wide administration except ownership transfer |
| Family Organizer | Highly trusted relative | Manage content and folders inside assigned branches |
| Contributor | Grandparent, relative, family friend | Create content and manage only their own content inside assigned scopes |
| Viewer | Trusted read-only family member | Read visible content inside assigned scopes |
| Recipient | Child or other intended recipient | Read only their own unlocked deliveries and optionally reply |

Role defaults can be narrowed or expanded with explicit grants and denials. Explicit denials always win.

## Family branches and folders

A **family branch** is both an organizational group and a permission boundary. Initial branches should include:

- Parents
- Maternal family
- Paternal family
- Chosen family
- Custom branches

Folders live inside branches and can be nested. Examples include:

- Maternal family / Grandma and Grandpa
- Paternal family / Holiday memories
- Parents / Birthday letters
- Chosen family / Family friends

A collaborator can be scoped to the entire archive, one or more branches, individual folders, one or more recipients, or a combination of those constraints.

## Why one giant CloudKit share is not sufficient

CloudKit share permissions are intentionally broad: participants are read-only or read/write for the records inside a share. The LettersToMy role engine provides product-level permissions such as edit-own versus edit-any, but sensitive boundaries must also be enforced by separate CloudKit shares.

LettersToMy therefore partitions collaboration into separate share roots:

- `archiveAdministration`
- `branch(<branch ID>)`
- `folder(<folder ID>)` when a narrower hard boundary is needed
- `recipientInbox(<recipient ID>)`

A spouse or co-parent is added to the administrative share and every relevant branch and recipient share. A grandparent receives only the branch or folder shares assigned to them. A viewer receives read-only shares. Contributors and organizers receive read/write shares for their assigned scopes.

## Recipient delivery model

Recipients do not join the share containing sealed master letters.

Each recipient receives a dedicated read-only inbox share. When a letter unlocks, the archive creates a delivery package in that inbox containing the released letter and its approved attachments. This prevents a recipient from discovering sealed record metadata, attachments, or future delivery dates through the shared database.

Recipients may optionally be allowed to:

- Reply to a delivered letter
- Add a memory to a separate contribution folder
- Download an unlocked delivery
- See or hide the contributor's identity

Those options are independent from access to the master archive.

## Invitation flow

1. An owner or authorized member chooses a role, relationship label, and scope.
2. The app creates a pending `CollaborationInvitation`.
3. The sharing layer maps the invitation to one or more `CollaborationShareGrant` values.
4. The app creates or fetches the corresponding private CloudKit shares.
5. Apple's sharing interface sends the invitations and manages CloudKit participants.
6. The invitee accepts the share and the app links the CloudKit participant to the local archive member.
7. Revoking membership removes the participant from every associated share.

Public share links are not used for family archives.

## Persistence requirement

The current SwiftData storage layer can mirror a private CloudKit database but cannot consume the shared CloudKit database required for collaboration. Before live invitations are enabled, persistence must migrate to `NSPersistentCloudKitContainer` with separate private and shared stores.

The migration should preserve the portable models and policies in `LettersToMyCore`; only the Apple persistence adapter and SwiftUI fetch layer need to change.

## Migration sequence

1. Add a versioned Core Data model matching the existing child, letter, attachment, branch, folder, member, invitation, and recipient-delivery records.
2. Configure `NSPersistentCloudKitContainer` with a private store and a shared store.
3. Import existing SwiftData records into the private Core Data store.
4. Replace SwiftData queries with Core Data fetches.
5. Add CloudKit invitation acceptance handling on iOS, iPadOS, and macOS.
6. Add the system sharing controller for creating and managing private shares.
7. Add delivery generation when a letter becomes unlocked.
8. Test with at least two separate iCloud accounts before promoting the CloudKit schema.

## Source of truth

- `Collaboration.swift` defines roles, scopes, invitations, and permission evaluation.
- `CollaborationSharePlan.swift` maps product roles to enforceable CloudKit share partitions.
- CloudKit participant permissions are transport-level protections.
- The permission evaluator remains the common behavior for Apple, web, and Android clients.

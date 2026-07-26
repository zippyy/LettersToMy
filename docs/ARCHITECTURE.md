# Architecture

## Product sequence

LettersToMy is intentionally Apple-first:

1. Native iPhone and iPad application
2. Native macOS application sharing the same SwiftUI and domain code
3. Web application connected to the same CloudKit container
4. Android application after the Apple and web data contracts are stable

This follows the architecture used for DankDiary rather than starting with a generic cross-platform shell.

## Native application

- **UI:** SwiftUI
- **Persistence and synchronization:** Core Data through `NSPersistentCloudKitContainer`
- **Owned data:** CloudKit private-database store
- **Accepted collaboration:** CloudKit shared-database store
- **Shared domain logic:** `LettersToMyCore`, a platform-neutral Swift package
- **Minimum targets:** iOS/iPadOS 17 and macOS 14

The app has separate iOS and macOS products but shares the implementation under `Sources/LettersToMy`.

## Persistent stores

The Core Data stack uses:

- `LettersToMy-private.sqlite` for records owned by the current iCloud user
- `LettersToMy-shared.sqlite` for records other archive owners share with the current user
- Persistent history and remote-change notifications
- A view context that automatically merges CloudKit imports
- Core Data and CloudKit record-level update and delete checks for shared objects

New owned objects are explicitly assigned to the private store. Objects created while editing accepted shared content are assigned to the same store as their parent object.

## Share partitions

`SharePartitionRecord` is the root of a Core Data CloudKit share. The current partition types are:

- Archive administration
- Family side
- Folder
- Recipient inbox

Letters and related attachments connect to their share partition through Core Data relationships. Branches, folders, children, members, and invitations also connect to their corresponding root. This provides enforceable CloudKit boundaries instead of relying only on client-side filtering.

Parent/admin access can require several shares because a single CloudKit record cannot belong to multiple independently permissioned share zones. The People & Access screen presents every required share through `ShareLink`.

## Stable identifiers

Records use stable UUID values for cross-platform references:

- Child and recipient IDs
- Letter IDs
- Attachment IDs
- Family branch IDs
- Folder IDs
- Archive member IDs
- Invitation IDs
- Share-partition IDs

Those identifiers remain stable across Core Data, CloudKit, the web adapter, exports, and a future Android client.

## Unlock rules

The portable core supports:

- A fixed calendar date
- A birthday calculated from a child profile and age
- A life event that remains sealed until a parent manually releases it

Unlock evaluation lives in `LettersToMyCore`, not in SwiftUI, so the same behavior can be reproduced and tested in the web and Android clients.

## Collaboration model

`LettersToMyCore` defines:

- Owner, parent/admin, organizer, contributor, viewer, and recipient roles
- Explicit grants and denials
- Archive, branch, folder, and recipient scopes
- Permission evaluation for viewing, creating, editing, deleting, releasing, inviting, exporting, and replying
- CloudKit share partition planning

CloudKit supplies broad read-only or read/write enforcement for each share. The app permission engine supplies finer product behavior such as edit-own versus edit-any. Sensitive boundaries are placed in separate shares so they do not depend only on client-side checks.

Recipients receive a dedicated read-only delivery inbox. Sealed master records are never shared with a recipient before release.

## Share invitation lifecycle

- SwiftUI `ShareLink` uses `CKShareTransferRepresentation` to create or manage a share.
- iOS routes accepted metadata through a custom `UIWindowSceneDelegate`.
- macOS routes accepted metadata through `NSApplicationDelegate`.
- Both platforms call `acceptShareInvitations(from:into:completion:)` and import accepted content into the shared store.

See `COLLABORATION.md` and `CORE_DATA_MIGRATION.md` for implementation details.

## Privacy boundary

Private family content is stored locally and synchronized through the signed-in user's iCloud account. A proprietary LettersToMy server is not required to hold letters or media for the Apple-first release.

Recovery contacts, encrypted archive export, succession handling, participant revocation, and multi-account testing must be completed before a public release because this product is designed to preserve content for decades.

## Web boundary

The future web application will use CloudKit JS or CloudKit Web Services with an API token and user authentication. It must use the native app's established CloudKit schema and never create an independent source of truth.

The web client must query owned data from the private scope and accepted collaboration from the shared scope, apply the same permission evaluator, and never infer access merely because it can name a record identifier.

See `CLOUDKIT_WEB.md` for the integration contract.

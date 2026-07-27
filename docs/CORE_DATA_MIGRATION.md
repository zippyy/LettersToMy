# Core Data and CloudKit Sharing

LettersToMy now uses `NSPersistentCloudKitContainer` instead of SwiftData for application persistence.

## Stores

The container loads two SQLite stores using the same managed-object model:

- `LettersToMy-private.sqlite` mirrors the signed-in user's private CloudKit database.
- `LettersToMy-shared.sqlite` mirrors shares that the signed-in user accepts from another archive owner.

Both stores enable persistent history tracking and remote-change notifications. The shared SwiftUI view context automatically merges imported changes.

## Share roots

`SharePartitionRecord` is the root object for a CloudKit zone share. Partitions currently represent:

- Archive administration
- Family sides
- Individual folders
- Recipient inboxes

Letters, attachments, branches, folders, children, members, and invitation metadata connect to a partition with Core Data relationships. Since iOS 16.4 and macOS 13.3, `NSPersistentCloudKitContainer` updates its maintained share as objects enter or leave the shared relationship graph.

## Creating invitations

The People & Access screen creates app-level invitation metadata and displays a SwiftUI `ShareLink` for every required partition. `CloudKitShareItem` uses `CKShareTransferRepresentation` to create a new `CKShare` or manage an existing share.

CloudKit controls the actual participant identity and broad read-only/read-write permission. `LettersToMyCore.CollaborationPolicy` applies the finer role rules inside the app.

## Accepting invitations

- iOS uses a custom `UIWindowSceneDelegate` and calls `acceptShareInvitations(from:into:completion:)` with the shared persistent store.
- macOS accepts metadata through `NSApplicationDelegate` and imports it into the same shared store.

The `CKSharingSupported` Info.plist key remains enabled for both products.

## Clean-cut migration

This repository has not shipped a production build, so the Core Data implementation starts with new `LettersToMy-private.sqlite` and `LettersToMy-shared.sqlite` stores. The previous SwiftData development database is not imported. A production release must not switch store implementations after users create data without adding an explicit importer.

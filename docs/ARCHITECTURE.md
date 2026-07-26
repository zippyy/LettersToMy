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
- **Prototype persistence:** SwiftData with private CloudKit mirroring
- **Production collaboration persistence:** Core Data through `NSPersistentCloudKitContainer`, with private and shared stores
- **Shared domain logic:** `LettersToMyCore`, a platform-neutral Swift package
- **Minimum targets:** iOS/iPadOS 17 and macOS 14

The app has separate iOS and macOS products but shares the implementation under `Sources/LettersToMy`.

## Persistence decision

SwiftData is useful for the initial single-family-device prototype, but its CloudKit integration cannot consume shared CloudKit databases. Collaboration is a core product requirement, so the production Apple persistence adapter will migrate to `NSPersistentCloudKitContainer`.

The Core Data stack will use:

- A private store for records owned by the current iCloud user
- A shared store for records other archive owners share with the current user
- CloudKit share roots partitioned by administration, family branch, folder, and recipient inbox
- Persistent history and remote-change notifications for responsive multi-device updates

The portable domain layer remains independent of Core Data. This prevents permission rules, unlock behavior, and share planning from becoming Apple-only code.

## Stable identifiers

Records use stable UUID values for cross-platform references:

- Child and recipient IDs
- Letter IDs
- Attachment IDs
- Family branch IDs
- Folder IDs
- Archive member IDs
- Invitation IDs

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

See `COLLABORATION.md` for the full permission and invitation design.

## Privacy boundary

Private family content is stored locally and synchronized through the signed-in user's iCloud account. A proprietary LettersToMy server is not required to hold letters or media for the Apple-first release.

Recovery contacts, encrypted archive export, succession handling, and revocation testing must be completed before a public release because this product is designed to preserve content for decades.

## Web boundary

The future web application will use CloudKit JS or CloudKit Web Services with an API token and user authentication. It must use the native app's established CloudKit schema and never create an independent source of truth.

The web client must apply the same permission evaluator and must never infer access merely because it can name a record identifier.

See `CLOUDKIT_WEB.md` for the integration contract.

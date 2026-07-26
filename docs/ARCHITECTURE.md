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
- **Persistence:** SwiftData
- **Synchronization:** SwiftData mirroring into the private CloudKit database
- **Shared domain logic:** `LettersToMyCore`, a platform-neutral Swift package
- **Large media:** SwiftData `externalStorage`, which allows the persistence layer to manage attachments separately from ordinary scalar fields
- **Minimum targets:** iOS/iPadOS 17 and macOS 14

The app has separate iOS and macOS products but shares the implementation under `Sources/LettersToMy`.

## Data model

The first schema deliberately avoids SwiftData relationships and uniqueness constraints. Records link through stable UUID values instead:

- `ChildProfile.id`
- `Letter.childID`
- `LetterAttachment.letterID`

That produces a simpler CloudKit representation for a future web client and reduces migration risk. All persisted values have defaults or are optional to remain compatible with CloudKit-backed SwiftData.

## Unlock rules

The portable core supports:

- A fixed calendar date
- A birthday calculated from a child profile and age
- A life event that remains sealed until a parent manually releases it

Unlock evaluation lives in `LettersToMyCore`, not in SwiftUI, so the same behavior can be reproduced and tested in the web and Android clients.

## Privacy boundary

For the Apple-first release, private family content is stored locally and synchronized to the signed-in user’s private CloudKit database. A proprietary LettersToMy server is not required to hold letters or media.

CloudKit sharing will later provide parent/caregiver collaboration. Recovery contacts, encrypted archive export, and succession handling must be completed before a public release because this product is designed to preserve content for decades.

## Web boundary

The future web application will use CloudKit JS or CloudKit Web Services with an API token and user authentication. It must use the native app’s established CloudKit schema and never create an independent source of truth.

See `CLOUDKIT_WEB.md` for the integration contract.

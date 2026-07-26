# LettersToMy

A private, Apple-first family time capsule for writing letters, preserving memories, and scheduling them to unlock throughout a child's life.

## Product direction

1. Native iPhone, iPad, and macOS app built with SwiftUI.
2. Private and shared iCloud synchronization through CloudKit.
3. Integrated web app using the same CloudKit container through CloudKit JS/Web Services.
4. Android client after the Apple and web experiences are established.

## Current milestone

The repository foundation contains:

- Shared SwiftUI screens for iPhone, iPad, and macOS
- `NSPersistentCloudKitContainer` with private and shared CloudKit-backed stores
- Persistent-history tracking, remote-change notifications, and automatic merging
- Draft, scheduled, and unlocked letter states
- Specific-date, birthday-age, and parent-released life-event rules
- Photo, video, and audio attachment ingestion
- Recipient preview mode that hides sealed content
- Owner, parent/admin, organizer, contributor, viewer, and recipient roles
- Archive, family-side, folder, and recipient permission scopes
- Explicit permission grants and denials
- Real CloudKit share creation and invitation acceptance
- Separate share roots for administration, family sides, folders, and recipient inboxes
- A portable Swift core package with automated tests
- A documented CloudKit contract for the future web client
- An XcodeGen project definition for separate iOS and macOS products

## Open the project

Install XcodeGen, then run:

```bash
brew install xcodegen
xcodegen generate
open LettersToMy.xcodeproj
```

Select your Apple Developer team in Xcode. The expected bundle identifiers are:

- `com.bayoumountainholdings.LettersToMy`
- `com.bayoumountainholdings.LettersToMy.mac`

Both products use the CloudKit container `iCloud.com.bayoumountainholdings.LettersToMy`.

## Test the portable core

```bash
swift test
```

## Development-store migration

LettersToMy has not shipped a production build, so the Core Data implementation starts with new private and shared stores. The earlier SwiftData development database is not imported. Do not change persistence implementations after release without adding an explicit user-data migration.

## Privacy

LettersToMy does not require a proprietary application server for the Apple-first release. Family content is stored locally and synchronized through the signed-in user's iCloud account. Content in private and shared CloudKit databases counts against the originating owner's iCloud storage.

See:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/COLLABORATION.md`](docs/COLLABORATION.md)
- [`docs/CORE_DATA_MIGRATION.md`](docs/CORE_DATA_MIGRATION.md)
- [`docs/CLOUDKIT_WEB.md`](docs/CLOUDKIT_WEB.md)

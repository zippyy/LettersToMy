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
- SwiftData models for the current private-archive prototype
- Draft, scheduled, and unlocked letter states
- Specific-date, birthday-age, and parent-released life-event rules
- Photo, video, and audio attachment ingestion
- Recipient preview mode that hides sealed content
- A portable Swift core package with automated tests
- Owner, parent/admin, organizer, contributor, viewer, and recipient roles
- Archive, family-branch, folder, and recipient permission scopes
- Explicit permission grants and denials
- CloudKit share planning for spouses, grandparents, other contributors, and recipients
- Separate read-only recipient inboxes that receive only unlocked deliveries
- A documented CloudKit contract for the future web client
- An XcodeGen project definition for separate iOS and macOS products

## Collaboration persistence migration

Live collaboration requires CloudKit's shared database. SwiftData's CloudKit integration currently handles the private database but not shared databases, so the production persistence layer will migrate to `NSPersistentCloudKitContainer` with private and shared stores before invitation delivery is enabled.

The collaboration domain and tests already live in `LettersToMyCore`, so the permission rules and share topology will remain shared across Apple, web, and Android clients.

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

## Privacy

LettersToMy does not require a proprietary application server for the Apple-first release. Family content is stored locally and synchronized through the signedSee:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/COLLABORATION.md`](docs/COLLABORATION.md)
- [`docs/CLOUDKIT_WEB.md`](docs/CLOUDKIT_WEB.md)

# LettersToMy

A private, Apple-first family time capsule for writing letters, preserving memories, and scheduling them to unlock throughout a child’s life.

## Product direction

1. Native iPhone, iPad, and macOS app built with SwiftUI.
2. Private iCloud synchronization through CloudKit.
3. Integrated web app using the same CloudKit container through CloudKit JS/Web Services.
4. Android client after the Apple and web experiences are established.

## Current milestone

The initial repository foundation contains:

- Shared SwiftUI screens for iPhone, iPad, and macOS
- SwiftData models prepared for private CloudKit synchronization
- Draft, scheduled, and unlocked letter states
- Specific-date, birthday-age, and parent-released life-event rules
- Photo, video, and audio attachment ingestion
- Recipient preview mode that hides sealed content
- A portable Swift core package with automated unlock-rule tests
- A documented CloudKit contract for the future web client
- An XcodeGen project definition for separate iOS and macOS products

Encrypted archive export, family CloudKit sharing, recovery contacts, and succession handling remain release requirements rather than unfinished security shortcuts.

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

LettersToMy does not require a proprietary application server for the Apple-first release. Family content is stored locally and synchronized to the user’s private CloudKit database when CloudKit is enabled. Content in a private CloudKit database belongs to the signed-in iCloud user and counts against that user’s iCloud storage.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) and [`docs/CLOUDKIT_WEB.md`](docs/CLOUDKIT_WEB.md).

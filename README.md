# LettersToMy

A private, Apple-first family time capsule for writing letters, recording memories, and scheduling them to unlock throughout a child’s life.

## Product direction

1. Native iPhone, iPad, and macOS app built with SwiftUI.
2. Private iCloud synchronization through CloudKit.
3. Integrated web app using the same CloudKit container through CloudKit JS/Web Services.
4. Android client after the Apple and web experiences are established.

## Current milestone

The initial repository foundation contains:

- A shared SwiftUI app for iOS, iPadOS, and macOS
- SwiftData models prepared for CloudKit synchronization
- Date- and age-based letter unlock rules
- Draft, scheduled, and unlocked views
- Portable `.letterstomy` archive export/import foundations
- An XcodeGen project definition

## Open the project

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), then run:

```bash
xcodegen generate
open LettersToMy.xcodeproj
```

Select your Apple Developer team in Xcode. The expected bundle identifier is `com.bayoumountainholdings.LettersToMy`, and the expected iCloud container is `iCloud.com.bayoumountainholdings.LettersToMy`.

## Privacy

LettersToMy does not require a proprietary application server for the Apple-first release. Family content is stored locally and synchronized to the user’s private iCloud database when CloudKit is enabled. Content in a private CloudKit database belongs to the signed-in iCloud user and counts against that user’s iCloud storage.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the implementation plan.

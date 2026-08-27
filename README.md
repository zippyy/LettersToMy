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

## Self-hosted server (optional add-on)

LettersToMy can optionally connect to a self-hosted
[LettersToMy-SelfHostedSync](https://github.com/zippyy/LettersToMy-SelfHostedSync)
server for server-side features. It is an **add-on**: CloudKit remains the
source of truth for your archive, and the app works fully offline or with no
server configured.

### What it enables

- **Server backup storage** — encrypted `.letterstomy` archives are uploaded to
  your server. The archive is encrypted with your passphrase before it leaves
  the device; the server stores an opaque blob and never sees the passphrase
  or plaintext letter content.
- **Cross-platform collaboration directory** — invitations, members, family
  branches, and folders shared through the server (usable by any client that
  speaks the same API).
- **Attachment storage** — opaque media blobs, byte-identical round trip.
- **Device snapshot storage** (`/sync`) — raw platform database files as
  backup artifacts. This is **not** logical cross-platform synchronization:
  a Core Data database cannot be swapped into an Android app or vice versa.
  The app does not expose snapshot push/pull in the UI and never hot-swaps a
  live SQLite file.

### Configure it

1. Deploy `LettersToMy-SelfHostedSync` (see its README).
2. In the app: **Settings → Self-Hosted Server**.
3. Enter the server URL (e.g. `https://letters.example.com` or
   `http://192.168.1.50:8080` for LAN testing) and the API token.
4. Enable Self-Hosted Integration and tap **Test Connection** — the app
   contacts `/status`, validates the service identity and API version, runs a
   full capability probe (collaboration, backup, attachment round trips), and
   reports a real connected/error state.

The API token is stored in the Keychain. The server URL and enabled state are
stored in UserDefaults. **Clear Configuration** removes all of it.

### When the server is offline

Nothing breaks. The app still launches, CloudKit still syncs, and local
backups still work. The self-hosted status shows *Server unreachable* and
backup to that destination fails with an explicit error — it never blocks
startup and never pretends to succeed.

### API contract

The client and server share a single versioned contract (API v1): structured
`{"error":{"code","message"}}` errors, Unix-millisecond timestamps, `[]` never
`null` collections, and role raw values identical to the app's
`CollaborationRole`. The `selfhosted-check` executable in this repository's
Swift package runs the full capability probe against a live server; the
server repo's `scripts/integration-test.sh` drives it end to end.

See:

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)
- [`docs/COLLABORATION.md`](docs/COLLABORATION.md)
- [`docs/CORE_DATA_MIGRATION.md`](docs/CORE_DATA_MIGRATION.md)
- [`docs/CLOUDKIT_WEB.md`](docs/CLOUDKIT_WEB.md)

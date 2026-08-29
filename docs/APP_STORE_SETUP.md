# App Store Connect, CloudKit, and Developer Setup

Complete step-by-step guide to get LettersToMy from a local build to a
TestFlight distribution with working CloudKit synchronization.

---

## 1. Apple Developer Program

1. Enroll at [developer.apple.com](https://developer.apple.com) ($99/year).
2. Accept the latest Developer Program License Agreement.
3. Verify your team name appears under **Membership**.
   - Expected team: **Bayou Mountain Holdings**
4. Add any additional team members under **People** with appropriate roles:
   - **Admin** — full access to certificates, profiles, App Store Connect
   - **Developer** — Xcode signing and CloudKit dashboard
   - **Marketer** — App Store Connect metadata only

---

## 2. App IDs

Create two App IDs under **Certificates, Identifiers & Profiles → Identifiers → App IDs**:

### 2.1 iOS App ID

| Field | Value |
|-------|-------|
| Description | Letters to My |
| Bundle ID (Explicit) | `com.bayoumountainholdings.LettersToMy` |
| Capabilities | CloudKit, Push Notifications |

After creation, enable **CloudKit** under the Capabilities tab if it was not
checked during creation. Verify the CloudKit container shows
`iCloud.com.bayoumountainholdings.LettersToMy`.

### 2.2 macOS App ID

| Field | Value |
|-------|-------|
| Description | Letters to My Mac |
| Bundle ID (Explicit) | `com.bayoumountainholdings.LettersToMy.mac` |
| Capabilities | CloudKit, Push Notifications, App Sandbox, Hardened Runtime |

Enable the same CloudKit container on the macOS App ID.

---

## 3. CloudKit Container

### 3.1 Verify container exists

Under **Identifiers → CloudKit Containers**, confirm
`iCloud.com.bayoumountainholdings.LettersToMy` is listed.

If it does not exist:
1. Click **+** to add a new CloudKit container.
2. Name it `iCloud.com.bayoumountainholdings.LettersToMy`.
3. Assign it to both App IDs.

### 3.2 CloudKit Console

Go to [CloudKit Console](https://icloud.developer.apple.com/dashboard/).

1. Select the container `iCloud.com.bayoumountainholdings.LettersToMy`.
2. Under **Schema**, the record types will appear automatically after the
   first development build syncs data — no manual schema creation is needed
   because `NSPersistentCloudKitContainer` generates the schema on first use.

   Expected record types after first sync:
   - `CD_ChildProfile`
   - `CD_Letter`
   - `CD_LetterAttachment`
   - `CD_FamilyBranchRecord`
   - `CD_ArchiveFolderRecord`
   - `CD_ArchiveMemberRecord`
   - `CD_CollaborationInvitationRecord`
   - `CD_SharePartitionRecord`
   - `CD_BackupRecordEntity`
   - `CD_DeliveryRecordEntity`
   - `CD_DeliveryAttachmentEntity`
   - `CD_RecoveryContactEntity`

   (Core Data prefixes record types with `CD_` when generating CloudKit schemas.)

3. The Development environment allows schema changes. After multi-account
   testing passes, promote the schema to **Production** under
   **Schema → Deployment**.

### 3.3 CloudKit Sharing

Verify sharing is enabled:

1. Under **Schema → Security Roles**, confirm:
   - **Authenticated** role has read/create on shared record types.
   - **World** has no access (public links are disabled for family archives).

2. The `CKSharingSupported` key is already set in both
   `Config/Info-iOS.plist` and `Config/Info-macOS.plist`.

---

## 4. Certificates and Provisioning Profiles

### 4.1 Development

Xcode will handle this automatically when you select your team for the
first time. Verify in Xcode:

1. Open `LettersToMy.xcodeproj`.
2. Select the **LettersToMy** target → Signing & Capabilities.
3. Team: Bayou Mountain Holdings.
4. Ensure **Automatically manage signing** is checked.
5. Repeat for the **LettersToMyMac** target.

### 4.2 Distribution (TestFlight / App Store)

1. Under **Certificates, Identifiers & Profiles → Profiles**:
2. Create an **iOS Distribution** profile for
   `com.bayoumountainholdings.LettersToMy`.
3. Create a **macOS Distribution** profile for
   `com.bayoumountainholdings.LettersToMy.mac`.
4. Download and double-click each profile to install.

Alternatively, let Xcode manage distribution signing automatically —
this is the simpler path for TestFlight builds.

---

## 5. Xcode Project Configuration

### 5.1 Confirm bundle identifiers

In `project.yml` these are already set:

```yaml
LettersToMy:
  PRODUCT_BUNDLE_IDENTIFIER: com.bayoumountainholdings.LettersToMy
LettersToMyMac:
  PRODUCT_BUNDLE_IDENTIFIER: com.bayoumountainholdings.LettersToMy.mac
```

### 5.2 Confirm entitlements

`Config/LettersToMy-iOS.entitlements` currently contains:

```xml
<key>com.apple.developer.icloud-container-identifiers</key>
<array>
    <string>iCloud.com.bayoumountainholdings.LettersToMy</string>
</array>
<key>com.apple.developer.icloud-services</key>
<array>
    <string>CloudKit</string>
</array>
```

`Config/LettersToMy-macOS.entitlements` contains the same CloudKit keys
plus the App Sandbox keys (mandatory for Mac App Store / TestFlight):

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>
<key>com.apple.security.network.client</key>
<true/>
```

`aps-environment` is intentionally NOT present yet: push notifications
are a future feature (see section 10). Add it when remote notifications
are implemented. CloudKit remote-change notifications are delivered
through the app's background modes, not through APNs.

### 5.3 Generate the project

```bash
brew install xcodegen      # if not already installed
xcodegen generate
```

---

## 6. App Store Connect

### 6.1 Create app records

Go to [App Store Connect](https://appstoreconnect.apple.com) → **My Apps** → **+** → **New App**.

#### iOS App

| Field | Value |
|-------|-------|
| Platform | iOS |
| Name | Letters to My |
| Primary Language | English |
| Bundle ID | `com.bayoumountainholdings.LettersToMy` |
| SKU | `LETTERSTOMY_IOS` |
| User Access | Full Access |

#### macOS App

| Field | Value |
|-------|-------|
| Platform | macOS |
| Name | Letters to My |
| Primary Language | English |
| Bundle ID | `com.bayoumountainholdings.LettersToMy.mac` |
| SKU | `LETTERSTOMY_MAC` |
| User Access | Full Access |

### 6.2 Required metadata (before TestFlight submission)

Under the iOS app record, fill in at minimum:

- **App Information**: Privacy Policy URL (see section 7)
- **Pricing and Availability**: Free (for now)
- **App Privacy**: Complete the privacy questionnaire
- **App Review Information**: Contact info, notes for review
- **Version Information**: What's new in this version

The macOS app record needs the same fields.

---

## 7. Privacy Policy

LettersToMy processes the following data types, all stored in the user's
private iCloud account and never sent to a LettersToMy server:

| Data type | Purpose | Linked to user? |
|-----------|---------|-----------------|
| Name (letters, profiles) | Core functionality | Yes |
| Photos/Videos (attachments) | Core functionality | Yes |
| Audio recordings | Core functionality | Yes |
| Email/phone (invitations) | App functionality | Yes |
| CloudKit user identity | App functionality | Yes |
| Crash data | Analytics | No |

Declare these in the App Privacy section. No third-party SDKs collect
analytics — only Apple's built-in crash reporting is used.

A privacy policy page must be hosted at a publicly accessible URL.
Template content is in `docs/PRIVACY_POLICY.md` (create when needed).

---

## 8. TestFlight

### 8.1 Archive and upload

```bash
# iOS
xcodebuild archive \
  -project LettersToMy.xcodeproj \
  -scheme LettersToMy \
  -archivePath ./build/LettersToMy-iOS.xcarchive

xcodebuild -exportArchive \
  -archivePath ./build/LettersToMy-iOS.xcarchive \
  -exportOptionsPlist Config/ExportOptions-iOS.plist \
  -exportPath ./build/iOS

# Upload via Xcode Organizer or:
xcrun altool --upload-app \
  -f ./build/iOS/LettersToMy.ipa \
  -t ios \
  --apiKey $APPSTORE_API_KEY_ID \
  --apiIssuer $APPSTORE_ISSUER_ID
```

Or use Xcode: Product → Archive → Distribute App → TestFlight.

### 8.2 Internal testing

1. In App Store Connect, go to **TestFlight → Internal Testing**.
2. Add your team members as testers.
3. The build appears after Apple's processing (usually 5-15 minutes).
4. Each tester gets an email invitation.

### 8.3 External testing

1. Create an **External Testing** group.
2. Add testers by email (up to 10,000).
3. Submit for Beta App Review (first build only, takes 24-48 hours).
4. Subsequent builds skip review unless the version number changes.

### 8.4 Build numbering

Increment `CURRENT_PROJECT_VERSION` in `project.yml` before each upload:

```yaml
settings:
  base:
    CURRENT_PROJECT_VERSION: 2   # was 1
```

Then regenerate and rebuild:
```bash
xcodegen generate
```

---

## 9. CloudKit Production Deployment

**Do not deploy the schema to production until these pass:**

- [ ] Private store syncs between two devices on the same iCloud account
- [ ] CKShare creation succeeds for each partition type
- [ ] A second iCloud account can accept and see shared content
- [ ] Recipient inbox shares do not expose sealed master records
- [ ] Revocation removes access within a reasonable time
- [ ] Relaunch preserves correct private/shared store behavior

### 9.1 Deploy to production

**Every signed build — TestFlight or App Store — talks to the Production
CloudKit environment.** A schema that exists only in Development is invisible
to those builds, and `NSPersistentCloudKitContainer` does not auto-create
schema in Production. A fresh install then exports record types the app
generated in Development, CloudKit rejects the unknown types, and the app
shows a sync error even though the account is healthy:

- Settings → iCloud shows **Account Available** together with
  **Export error: The operation couldn't be completed. (CKErrorDomain
  error 2.)**
- Error 2 is `CKError.partialFailure`. The top-level message hides the real
  cause; since build 44 the app surfaces per-record details (record ID +
  CKError code) in the same location. A missing record type typically shows
  as `CKError 11` (unknown item) on the rejected `CD_*` records.

To deploy:

1. Open [CloudKit Console](https://icloud.developer.apple.com/dashboard).
2. Select the container `iCloud.com.bayoumountainholdings.LettersToMy`.
3. In the **Development** environment, confirm the expected `CD_*` record
   types exist (they are generated automatically on first sync from a
   development build).
4. Go to **Schema → Deployment**.
5. Review the Development → Production diff carefully. Deployment is
   forward-only: destructive changes cannot be rolled back via the console.
6. Click **Deploy to Production**.

After deployment: relaunch the app — pending exports retry automatically and
the error clears once the rejected records upload. Then verify on a **clean
iCloud account** (one that has never run the app) so the fresh-install path is
exercised, not just an account with existing sync history.

### 9.1.1 Verifying with CloudKit Console logs

Use **CloudKit Console → Logs** (production) to confirm which record type a
reported `CKErrorDomain error 2` (`partialFailure`) rejection is actually
about:

- If the only failures are `RecordSave`/`RecordDelete` of **`_pcs_data`**
  (`overallStatus: USER_ERROR`, `error: BAD_REQUEST`, zone
  `com.apple.coredata.cloudkit.zone`) while your own `CD_*` `RecordSave`
  operations succeed, the schema is fine and **no deploy fixes it**:
  `_pcs_data` is a server-managed system record used by
  `NSPersistentCloudKitContainer`; there is no developer action (Console or
  cktool) that can add it to Production. This is the known Apple-side issue
  tracked as FB24378074 (Apple Developer Forums threads 838743, 842760,
  840248). Fixes have landed in OS releases and server-side incident
  resolutions; retest after iOS updates.
- If failures name a `CD_*` record type or show `CKError 11` (unknown item),
  the schema deploy above applies.

### 9.2 Production security roles

After deployment, verify under **Schema → Security Roles**:

| Record type | Authenticated | World |
|-------------|--------------|-------|
| All types | Read/Write (private DB) | None |
| Shared types | Read or Read/Write (per share) | None |

**World** (unauthenticated) must have zero access to every record type.

---

## 10. Push Notifications (future)

If you add push notifications for delivery alerts or invitations:

1. Under **Certificates, Identifiers & Profiles → Keys**, create an
   **APNs Auth Key**.
2. Download the `.p8` file (store securely — one download only).
3. Note the Key ID and Team ID.
4. When the server component is built, configure it with these credentials.

---

## 11. App Store Submission Checklist

Before submitting for App Store review:

- [ ] Privacy policy URL is live
- [ ] App Privacy questionnaire is complete
- [ ] Screenshots for all required device sizes (6.7" iPhone, 6.5" iPhone,
      12.9" iPad, Mac)
- [ ] App icon is set (currently using a placeholder)
- [ ] No references to "beta" or "test" in the app description
- [ ] All CloudKit schemas deployed to production and verified with a signed
      TestFlight or App Store build on a clean iCloud account
- [ ] Multi-account collaboration tested with production CloudKit
- [ ] Export compliance: uses standard encryption (AES-256-GCM for backups)
      — answer "Yes" to export compliance and select the exempt option
- [ ] Age rating questionnaire completed
- [ ] App Review Information filled in (sign-in demo account if applicable)
- [ ] Copyright line: "© 2026 Bayou Mountain Holdings"

---

## 12. Quick Reference

| Resource | URL |
|----------|-----|
| Developer Portal | https://developer.apple.com/account |
| App Store Connect | https://appstoreconnect.apple.com |
| CloudKit Console | https://icloud.developer.apple.com/dashboard |
| TestFlight Guide | https://developer.apple.com/testflight |
| App Review Guidelines | https://developer.apple.com/app-store/review |
| Certificates & IDs | https://developer.apple.com/account/resources/certificates/list |

---

## 13. Local Commands

```bash
# Regenerate Xcode project
xcodegen generate

# Run tests
swift test

# Build for iOS simulator
xcodebuild \
  -project LettersToMy.xcodeproj \
  -scheme LettersToMy \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

# Build for macOS
xcodebuild \
  -project LettersToMy.xcodeproj \
  -scheme LettersToMyMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

# Check CloudKit status in logs
xcrun simctl spawn booted log stream --predicate 'subsystem contains "CloudKit"'
```

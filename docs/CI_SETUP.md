# GitHub Actions CI/CD

LettersToMy uses GitHub Actions for continuous validation, TestFlight
distribution, and notarized macOS GitHub Releases. There is no fastlane:
signing uses base64 certificates and provisioning profiles stored as
repository secrets (the same pattern used for DankDiary).

## Workflows

### 1. Core tests — `.github/workflows/core-tests.yml`

Triggered on push to `main` and on pull requests.

Runs `swift test` (the portable `LettersToMyCore` package). This is the
fastest signal and covers unlock rules, collaboration policy, share
planning, delivery pipeline, and backup round-trips.

### 2. Apple builds — `.github/workflows/apple-build.yml`

Triggered on push to `main` and on pull requests.

- Installs XcodeGen and regenerates `LettersToMy.xcodeproj`
- Builds the iOS app (`-scheme LettersToMy`, iOS Simulator, unsigned)
- Builds the macOS app (`-scheme LettersToMyMac`, unsigned)
- Uploads `ios-diagnostics.txt` / `macos-diagnostics.txt` artifacts on
  every run (including failures) so build warnings/errors are visible

Both builds fail the job on error — `|| true` is never used to mask a
failed build.

### 3. Deploy to TestFlight — `.github/workflows/testflight.yml`

Manual dispatch only (`workflow_dispatch`) with inputs:

- `platform`: `ios`, `macos`, or `both`
- `build_number`: required, monotonically increasing (bump it every run;
  never reuse a number — App Store Connect rejects duplicate build
  numbers and CI must never be made idempotent on an existing tag)

Highlights:

- `sed` replaces `CURRENT_PROJECT_VERSION` in `project.yml` with the
  supplied build number, and replaces the
  `CI_IOS_PROFILE_UUID_PLACEHOLDER` / `CI_MACOS_PROFILE_UUID_PLACEHOLDER`
  markers so the manual provisioning profile is scoped to the app target
  only (global xcodebuild flags would apply it to SwiftPM package
  targets like Firebase, which fail with "does not support provisioning
  profiles").
- Imports the Apple Distribution certificate into a temporary keychain,
  installs the provisioning profile, installs the ASC API key into
  `~/private_keys`.
- Archives with `CODE_SIGN_STYLE=Manual` and exports.
- macOS export falls back to building the PKG manually from the
  xcarchive (`productbuild --component`) because Xcode 26.5's export cannot
  validate the Mac Installer cert against the provisioning profile —
  this is an intentional, documented fallback, not a masked failure;
  the step still fails if the app directory is missing.
- Uploads the IPA (iOS, via `xcrun altool`) or PKG (macOS, via
  Transporter — `iTMSTransporter -m upload`; `altool --upload-app` is
  rejected by App Store Connect on current Xcode with error -22421, and
  `notarytool` is the notarization service, not an App Store Connect
  delivery channel). The macOS job downloads Apple's standalone
  `itmstransporter.pkg` (fetched from Apple's
  `WebObjects/iTunesConnect.woa/ra/resources/download/public/Transporter__OSX/bin/`
  endpoint — the old `/itms/download/itmstransporter.pkg` URL now returns
  HTML, not a package) and installs it because macOS runners do not ship
  a working Transporter.
- Uploads the IPA/PKG artifact (fails if no file was found).
- A `summary` job prints a platform-by-platform status table, including
  the macOS TestFlight PKG file name.

macOS App Store validation notes (errors seen live on CI):

- The macOS app icon must be a real `AppIcon-Mac.appiconset` with a 1024px
  `icon-512-2x.png` and `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon-Mac`.
  The generated `AppIcon-Mac.icns` is what App Store Connect validates
  (ITMS-90236 otherwise).
- The macOS entitlements must contain
  `com.apple.developer.icloud-container-environment = Production` for App
  Store uploads (ITMS-90046 otherwise). The Developer ID release workflow
  strips this key because Developer ID distribution does not support it.

### 4. macOS GitHub Release — direct download — `.github/workflows/macos-release.yml`

This is a SEPARATE distribution channel from Mac App Store / TestFlight.
It produces a **Developer ID** signed, notarized, stapled `.pkg` that users
install directly from GitHub. It is NOT the App Store package.

Triggered by:

- Push of a `v*` tag (e.g. `v0.2.0`) — production path; version is derived
  from the tag.
- `workflow_dispatch` — controlled testing. `version` input sets the
  version/tag; `create_release=false` builds, signs, notarizes, and uploads
  artifacts WITHOUT touching the GitHub Release.

Never runs on plain pushes to `main`.

Flow:

1. Install XcodeGen, decode the Developer ID provisioning profile (UUID
   extracted from the profile itself), `sed` the
   `CI_MACOS_PROFILE_UUID_PLACEHOLDER` + `MARKETING_VERSION` in
   `project.yml`, regenerate the project.
2. Import BOTH Developer ID `.p12`s (Application + Installer) into a
   temporary keychain with `-T /usr/bin/{codesign,security,xcodebuild,
   xcrun,pkgbuild,productbuild}` and
   `security set-key-partition-list`, so no GUI/keychain prompt can block
   CI (this is what previously hung package creation).
3. `xcodebuild archive` with `CODE_SIGN_STYLE=Manual`,
   `CODE_SIGN_IDENTITY="Developer ID Application"`.
4. Verify the archived `.app`: exactly one `.app`, `codesign --verify
   --deep --strict`, `codesign -dv`.
5. `productbuild --component <app> /Applications --sign "Developer ID
   Installer: ..."` → `LettersToMy-<version>-macOS.pkg`, then
   `pkgutil --check-signature`.
6. Notarize: `xcrun notarytool submit --wait --output-format json`, then
   explicitly fail unless the parsed verdict is `Accepted` (`notarytool`
   exits 0 even on `Invalid`). No async fire-and-forget.
7. Staple: `xcrun stapler staple` + `stapler validate`, then
   `spctl --assess --type install` (advisory).
8. `shasum -a 256` → `.sha256`; upload pkg + checksum as workflow
   artifacts AND as GitHub Release assets (`gh release create` with
   `--generate-notes`, or `gh release upload --clobber` to update an
   existing release with only our same-named assets).

## Required secrets

Set these in GitHub → repository → Settings → Secrets and variables →
Actions:

| Secret | Used by | Description |
|--------|---------|-------------|
| `APPLE_DISTRIBUTION_CERTIFICATE_BASE64` | testflight | Base64 of the distribution `.p12` |
| `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD` | testflight | `.p12` passphrase |
| `APPLE_PROVISIONING_PROFILE_BASE64` | testflight (iOS) | Base64 of the iOS distribution profile (UUID `b45ab7db-22b5-4323-aa81-b881079901b5`) |
| `APPLE_PROVISIONING_PROFILE_BASE64_MAC` | testflight (macOS) | Base64 of the macOS distribution profile (UUID `91405fb4-afd9-4825-96a1-893de956e073`) |
| `APPLE_MAC_INSTALLER_CERTIFICATE_BASE64` | testflight (macOS) | Base64 of the 3rd Party Mac Developer Installer `.p12` |
| `APPLE_TEAM_ID` | testflight | Apple Developer Team ID (e.g. `B6LWQPCDFR`) |
| `ASC_KEY_ID` | testflight | App Store Connect API key ID |
| `ASC_ISSUER_ID` | testflight | App Store Connect API issuer ID |
| `ASC_KEY` | testflight | Base64 of the `.p8` API key, saved as `AuthKey_<KEY_ID>.p8` |

### GitHub Release (Developer ID) secrets

Required by `.github/workflows/macos-release.yml` — none exist yet; the
repository owner must create them:

| Secret | Used by | Description |
|--------|---------|-------------|
| `APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64` | release | Base64 of the **Developer ID Application** `.p12` (signs the public `.app`) |
| `APPLE_DEVELOPER_ID_INSTALLER_CERTIFICATE_BASE64` | release | Base64 of the **Developer ID Installer** `.p12` (signs the public `.pkg`) |
| `APPLE_DEVELOPER_ID_CERTIFICATE_PASSWORD` | release | `.p12` passphrase for the two Developer ID certs (reuse the same password if the exports share it) |
| `APPLE_DEVELOPER_ID_PROVISIONING_PROFILE_BASE64` | release | Base64 of the **Developer ID provisioning profile** (required: the app uses CloudKit + keychain access groups, which need a profile even for Developer ID distribution) |

`APPLE_TEAM_ID`, `ASC_KEY`, `ASC_KEY_ID`, `ASC_ISSUER_ID` are reused from
the TestFlight table — the same App Store Connect API key authenticates
`notarytool`.

### Certificate classes — do not conflate

| Channel | App signing identity | Package signing identity |
|---------|----------------------|--------------------------|
| iOS TestFlight | `Apple Distribution` | n/a (`.ipa`) |
| macOS TestFlight / Mac App Store | `Apple Distribution` | `3rd Party Mac Developer Installer` |
| macOS GitHub Release (direct download) | `Developer ID Application` | `Developer ID Installer` |

`Apple Distribution` and `Developer ID Application` are DIFFERENT
certificate classes and are NOT interchangeable. Same for
`3rd Party Mac Developer Installer` vs `Developer ID Installer`. The mac
App Store provisioning profile (`91405fb4-…`) authorizes only `Apple
Distribution`; the Developer ID profile is a separate profile for the
`Developer ID Application` cert.

**All certificates/profiles live in GitHub Actions secrets — never commit
them to the repository.** (The repo is scanned by CI; `.p12`, `.p8`,
`.mobileprovision`, and private keys are not tracked and must never be
added.)

The provisioning profile UUIDs in the workflow must match the profile's
own UUID (the workflow installs the file under both the short and full
UUID filenames). If you regenerate a profile, update both the UUID in
`testflight.yml` and the `PROVISIONING_PROFILE_SPECIFIER` markers in
`project.yml`.

## Build numbers

- `MARKETING_VERSION` (CFBundleShortVersionString) lives in
  `project.yml` under `settings.base` — bump it for releases.
- `CURRENT_PROJECT_VERSION` (CFBundleVersion) is set per-run from the
  `build_number` input. Never reuse a version/tag number.

## Local equivalents

```bash
# Core tests
swift test

# Regenerate the Xcode project after editing project.yml
xcodegen generate

# Unsigned builds (no signing required)
xcodebuild -project LettersToMy.xcodeproj -scheme LettersToMy \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project LettersToMy.xcodeproj -scheme LettersToMyMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `No provisioning profile found` | Confirm the profile UUID in `testflight.yml` matches the installed profile and that `APPLE_PROVISIONING_PROFILE_BASE64` is current |
| `code sign: errSecInternalComponent` | Re-create the build keychain in the workflow job; keychain corruption is transient per-run |
| `does not support provisioning profiles` | Ensure the profile is scoped via `project.yml` markers, not passed as a global `xcodebuild` flag |
| `Unable to find destination` | The hosted runner's Xcode version must have the iOS runtime installed for simulator builds |
| `Upload failed: Invalid build number` | The `build_number` input was reused — bump it |
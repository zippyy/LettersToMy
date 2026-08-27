# GitHub Actions CI/CD

LettersToMy uses GitHub Actions for continuous validation and
TestFlight distribution. There is no fastlane: signing uses base64
certificates and provisioning profiles stored as repository secrets
(the same pattern used for DankDiary).

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
  xcarchive (`pkgbuild --component`) because Xcode 26.5's export cannot
  validate the Mac Installer cert against the provisioning profile —
  this is an intentional, documented fallback, not a masked failure;
  the step still fails if the app directory is missing.
- Uploads to TestFlight via `xcrun altool` with the ASC key.
- Uploads the IPA/PKG artifact (fails if no file was found).
- A `summary` job prints a platform-by-platform status table.

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
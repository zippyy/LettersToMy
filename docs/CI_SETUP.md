# GitHub Actions CI/CD — TestFlight Deployment

## Overview

GitHub Actions builds both iOS and macOS apps, signs them with fastlane
Match, and uploads to TestFlight automatically when a release is
published (or manually via workflow_dispatch).

```
GitHub Release → Workflow → xcodegen → fastlane match (signing)
  → build_app → upload_to_testflight → Internal Testers
```

## Required Secrets

Set these in your GitHub repo under **Settings → Secrets & Variables →
Actions → Repository secrets**:

| Secret | Description | How to get |
|--------|-------------|------------|
| `ASC_KEY_ID` | App Store Connect API Key ID | [App Store Connect → Users → Keys](https://appstoreconnect.apple.com/access/integrations/api) |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID | Same page as above |
| `ASC_KEY` | Base64-encoded `.p8` private key | Download .p8, then `base64 -i AuthKey_XXXX.p8 \| tr -d '\n'` |
| `MATCH_PASSWORD` | Passphrase for the match git repo | Set when you first ran `fastlane match` |
| `MATCH_GIT_URL` | Git clone URL for the match repo | e.g. `https://github.com/zippyy/letters-to-my-certs.git` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | (if private repo) GitHub PAT or token | `echo -n 'username:token' \| base64` |
| `FASTLANE_APPLE_EMAIL` | Apple ID email for the developer account | Your Apple Developer login |
| `FASTLANE_TEAM_ID` | Apple Developer Team ID | [developer.apple.com → Membership](https://developer.apple.com/account) |

## App Store Connect API Key Setup

1. Go to [App Store Connect → Users and Access → Integrations → API Keys](https://appstoreconnect.apple.com/access/integrations/api).

2. Click **+** to create a new key:
   - Name: `GitHub Actions CI`
   - Role: **App Manager** (needed to upload builds and manage TestFlight)

3. Download the `.p8` file — **this is the only time you can download it**.

4. Convert to base64 for the `ASC_KEY` secret:
   ```bash
   base64 -i AuthKey_XXXXXX.p8 | tr -d '\n' | pbcopy
   ```
   Paste into the GitHub secret. No line breaks.

5. Note the **Key ID** (e.g. `ABC123DEF4`) and **Issuer ID** (UUID in the
   table header).

## Fastlane Match — First-Time Setup

Match stores your signing certificates and provisioning profiles in a
private git repo. Run these commands once on your Mac:

```bash
cd LettersToMy
bundle install

# Create a private git repo for certificates (e.g. on GitHub).
# Then configure it:
bundle exec fastlane match init

# Edit fastlane/Matchfile and set git_url to your repo URL.

# Generate App Store certs and profiles:
bundle exec fastlane match appstore

# Generate Development certs and profiles (for local builds):
bundle exec fastlane match development

# Set a strong passphrase when prompted — this becomes MATCH_PASSWORD.
```

After setup, commit only the `fastlane/Matchfile` — the certificates
themselves live in the match git repo, not in the LettersToMy repo.

## Triggering a Deploy

### Option 1: Publish a GitHub Release

1. Go to **Releases** → **Draft a new release**.
2. Tag: `v0.1.0` (or any semver tag).
3. Title: same as tag.
4. Description: this becomes the TestFlight "What to Test" notes.
5. Click **Publish release**.

The workflow runs automatically. Both iOS and macOS build in parallel
(~20-30 minutes total), then upload to TestFlight.

### Option 2: Manual Dispatch

1. Go to **Actions** → **Deploy to TestFlight** → **Run workflow**.
2. Choose platform: `ios`, `mac`, or `both`.
3. Optionally enter "What to Test" notes.
4. Click **Run workflow**.

## Build Numbers

The workflow uses `GITHUB_RUN_NUMBER` as the build number (CFBundleVersion).
This guarantees every upload has a unique, monotonically increasing build
number. The marketing version (CFBundleShortVersionString) is set in
`project.yml` under `MARKETING_VERSION`.

To bump the version for a release:

```bash
# Edit Config/project.yml
# Change: MARKETING_VERSION: 0.2.0
# Then: xcodegen generate
# Commit and push.
```

## Monitoring

After a workflow run:

1. **GitHub Actions**: check the workflow run for build logs.
2. **App Store Connect → TestFlight**: the build appears under
   **TestFlight → iOS (or macOS) → Builds** after processing (5-15 min).
3. **Internal testers** get the build automatically.
4. **External testers** need the build assigned to their group (set
   `distribute_external: true` in the Fastfile or use the App Store
   Connect UI).

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `No provisioning profile found` | Run `fastlane match appstore --force` to regenerate profiles |
| `Authentication failed` | Verify ASC_KEY is base64 with no line breaks |
| `Certificate has expired` | Run `fastlane match nuke appstore` then `fastlane match appstore` |
| `Build processing timeout` | App Store processing can take 30+ min. The lane uses `skip_waiting_for_build_processing: true` to return immediately |
| `xcodebuild: error: Unable to find destination` | Verify the selected Xcode version has the iOS runtime installed |
| `Match cannot decrypt repo` | Verify MATCH_PASSWORD and MATCH_GIT_BASIC_AUTHORIZATION |

## macOS Notarization

macOS apps distributed through TestFlight do not require separate
notarization — Apple handles it as part of App Store distribution.
If you later distribute outside the App Store, add a notarization lane:

```ruby
lane :notarize do
  notarize(
    package: "build/macos/LettersToMy.pkg",
    apple_id: ENV["FASTLANE_APPLE_EMAIL"],
    team_id: ENV["FASTLANE_TEAM_ID"]
  )
end
```

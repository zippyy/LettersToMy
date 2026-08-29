# Changelog

All notable changes to LettersToMy are recorded here. The app targets
iPhone, iPad, and macOS. Versioning follows `MARKETING_VERSION`
(currently `0.1.0`); build numbers are per-archive (see
`CURRENT_PROJECT_VERSION`).

## [Unreleased]

### Fixed

- **CloudKit error diagnostics** — a `CKError.partialFailure` (export/import
  errors) now surfaces the per-record underlying errors (record ID + CKError
  code + message, capped at 10) instead of the generic "The operation
  couldn't be completed. (CKErrorDomain error 2.)" message. Makes schema /
  record-rejection issues visible in Settings → iCloud.

## [0.1.0] - 2026-08-28

First tagged release. Paired with LettersToMy-SelfHostedSync **v0.3.0**
(wire contract: **API v1**).

### Added

- **Self-hosted backup restore** — restore an encrypted `.letterstomy`
  archive directly from a self-hosted server: list remote backups, choose,
  enter the passphrase, preview the archive contents, and confirm the
  import.
- **Self-hosted backup metadata** — server listings show letter counts
  persisted via the backup metadata sidecar (`letter_count`); the client
  reports the count from its own manifest.
- **Self-hosted server configuration** — Settings → Self-Hosted Server:
  URL + API token (Keychain-backed), Test Connection validates service
  identity, API version, and capabilities before anything is enabled.
- **Offline tolerance** — the app works fully with no server configured;
  unreachable-server states surface explicit errors and never block
  startup.

### Fixed

- **Restore no longer reports false success** — a failed Core Data save
  now aborts the import and surfaces an honest error instead of claiming
  "Imported N records".
- **Malformed/duplicate archive records** — attachment relinking is
  tolerant of duplicate letter IDs from corrupt or malicious archives
  (last-write-wins) instead of trapping; the restore path stays crash-free.
- **Swift concurrency fixes** — actor isolation corrected across the
  self-hosted restore flow and backup service.

### Compatibility

- API: **v1** (unchanged).
- Server: LettersToMy-SelfHostedSync **v0.3.0** — same contract.
- CloudKit remains the source of truth for the archive; the self-hosted
  server is an optional add-on.

### Notes

- First tagged release; earlier history used `restore-point-*` snapshot
  tags, which are not releases.
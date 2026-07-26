# CloudKit and Web Integration

## Container

- Native iOS bundle: `com.bayoumountainholdings.LettersToMy`
- Native macOS bundle: `com.bayoumountainholdings.LettersToMy.mac`
- Shared container: `iCloud.com.bayoumountainholdings.LettersToMy`

The container must be created and assigned to both app identifiers in the Apple Developer portal before signed builds can synchronize.

## Native setup

1. Generate the Xcode project with XcodeGen.
2. Select the Bayou Mountain Holdings development team for both app targets.
3. Confirm the iCloud/CloudKit and remote-notification capabilities.
4. Run a development build while signed into iCloud.
5. Create sample records and inspect the development environment in CloudKit Console.
6. Promote the schema to production only after migrations and test data have been reviewed.

## Web setup

The future web app will:

1. Load Apple’s hosted CloudKit JS library or call CloudKit Web Services.
2. Configure `iCloud.com.bayoumountainholdings.LettersToMy` with a web API token.
3. Authenticate the user before accessing the private database.
4. Read and write the same records created by the native app.
5. Preserve UUID linkage and unlock-rule semantics from `LettersToMyCore`.

Because SwiftData mirrors through Core Data, the exact generated CloudKit record and field names must be captured from CloudKit Console after the first development build. That generated schema becomes the authoritative mapping for the web adapter.

## Required before web development

- Freeze version 1 of the native data model
- Record generated CloudKit names in this document
- Add fixture records for every unlock rule and attachment type
- Add a web API token restricted to approved origins
- Define conflict behavior and offline reconciliation
- Add encrypted export/recovery rather than relying exclusively on a live vendor service

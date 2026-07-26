# CloudKit and Web Integration

## Container

- Native iOS bundle: `com.bayoumountainholdings.LettersToMy`
- Native macOS bundle: `com.bayoumountainholdings.LettersToMy.mac`
- Shared container: `iCloud.com.bayoumountainholdings.LettersToMy`

The container must be created and assigned to both app identifiers in the Apple Developer portal before signed builds can synchronize.

## Native setup

1. Generate the Xcode project with XcodeGen.
2. Select the Bayou Mountain Holdings development team for both app targets.
3. Confirm the iCloud/CloudKit, CloudKit Sharing, and remote-notification capabilities.
4. Run a development build while signed into iCloud.
5. Create sample owned and shared records using separate iCloud accounts.
6. Inspect the development schema in CloudKit Console.
7. Promote the schema to production only after migrations, sharing, and revocation tests have been reviewed.

## Web setup

The future web app will:

1. Load Apple's hosted CloudKit JS library or call CloudKit Web Services.
2. Configure `iCloud.com.bayoumountainholdings.LettersToMy` with a web API token.
3. Authenticate the user before accessing private or shared records.
4. Read the user's owned records from the private database.
5. Read records shared by another archive owner from the shared database.
6. Preserve UUID linkage, unlock rules, collaboration scopes, and share partitions from `LettersToMyCore`.
7. Apply `CollaborationPolicy` before presenting or mutating content.

CloudKit JS exposes private and shared database scopes. The web adapter must query both and merge the results without treating shared records as if the current user owns them.

## Collaboration behavior

- Parent/admin users may own one archive and participate in another.
- Branch and folder shares remain separate security boundaries.
- Recipient inboxes are read-only by default.
- Sealed master records are never fetched through a recipient inbox.
- A web client must respect CloudKit's participant permission and the finer LettersToMy role policy.
- Removing a participant must invalidate cached shared data and locally stored capabilities.

## Schema contract

The exact CloudKit record and field names must be captured after the Core Data collaboration schema is initialized in the development environment. That generated schema becomes the authoritative mapping for the web adapter.

The schema document must identify:

- Record type and field names
- Private versus shared store origin
- Share-root partition type
- Stable UUID fields
- Parent/reference relationships
- Asset fields and attachment limits
- Fields that a read-only recipient may receive

## Required before web development

- Complete the Core Data private/shared-store migration
- Freeze version 1 of the collaboration data model
- Record generated CloudKit names in this document
- Add fixture records for every unlock rule, role, scope, share partition, and attachment type
- Add a web API token restricted to approved origins
- Define conflict behavior and offline reconciliation
- Add participant revocation and cache-clearing tests
- Add encrypted export/recovery rather than relying exclusively on a live vendor service

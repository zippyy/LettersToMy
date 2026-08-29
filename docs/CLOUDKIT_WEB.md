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

### Production deployment gate

The development schema is **not** automatically the production schema. Before
shipping a production or TestFlight build, deploy the reviewed CloudKit schema
from the Development environment to Production in CloudKit Console.

The production schema must include every Core Data entity and field used by the
current app model — including private/shared collaboration records,
attachments, recovery contacts, delivery records, and backup metadata. After
deployment, test with a **clean iCloud account** (one that has never run the
app) and verify both private- and shared-store export/import behavior.

Do not treat `CKAccountStatus.available` as proof the schema is complete: an
available account can still surface `CKError.partialFailure` (`CKErrorDomain
error 2`, e.g. "Export error") when the app writes record types that only
exist in the Development schema. Since build 44, the app reports the specific
rejected record IDs and CKError codes in Settings → iCloud.

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

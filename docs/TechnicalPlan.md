# Carte technical plan

## Current architecture

- **iOS app:** `Carte.xcodeproj` contains a SwiftUI application target for TestFlight handoff.
- **Core package:** `CarteCore` owns card/domain invariants.
- **Feature package:** `CarteFeature` owns app state, transports, profile/contact/archive storage, CloudKit integration, and SwiftUI screens.
- **Secure identity:** `CloudKitIdentityDirectory` binds one Carte profile to CloudKit's `userRecordID()` for the signed-in iCloud account, then assigns a global integer Carte number from a CloudKit counter.
- **Serverless transit:** `CloudKitCardTransport` uses CloudKit only as a temporary delivery queue addressed by Carte number. Once the recipient dismisses an examined tray card, the app saves it to the local JSON archive and deletes the CloudKit transit records.
- **Local library:** `JSONProfileStore` persists `profile.json`, `contacts.json`, and `archive.json` in Application Support.

## Card lifecycle

1. Sender composes a card locally.
2. The sender enters the recipient's Carte number on the keypad.
3. `IdentityDirectory` resolves that number to the recipient profile/contact.
4. `CardTransport.send` creates a transient per-recipient-number delivery copy in CloudKit.
5. Recipient refreshes the Tray and examines the card.
6. Recipient taps **Done**.
7. `CarteAppState.dismissToArchive(_:)` stamps `archivedAt`, writes the card to local archive storage, and acknowledges the transit delivery by deleting it remotely.
8. Archive browsing reads from local storage only.
9. Erasing a tray card deletes the transit copy without archiving; erasing an archive card deletes the local copy only.

## CloudKit records

CloudKit stores these records only while a card is in transit.

### `CarteIdentity`

- recordName: CloudKit iCloud user record name
- `appUserID: String` UUID used by local card models
- `displayName: String`
- `inviteCode: String` legacy UUID invite string
- `userNumber: Int64` global Carte address, allocated from 0 upward
- `iCloudUserRecordName: String`
- `secureIdentityVersion: Int64`
- `createdAt: Date`
- `updatedAt: Date`

### `CarteNumberCounter`

- recordName: `global`
- `nextNumber: Int64` next Carte number to assign

### `Card`

- recordName: transient card UUID
- `senderID: String`
- `senderDisplayName: String`
- `senderNumber: Int64?`
- `createdAt: Date`
- `sentAt: Date`
- `lifecycle: String`
- `sidesData: Data` JSON-encoded `[CardSide]`

### `CardDelivery`

- recordName: delivery UUID
- `cardID: String`
- `recipientID: String` local app UUID fallback
- `recipientNumber: Int64` primary address
- `senderID: String`
- `deliveredAt: Date`

## Before TestFlight

- Replace placeholder bundle/container identifiers with production identifiers.
- Create CloudKit schema in Development by running the app once.
- Add indexes for identity and delivery queries and deploy schema to Production (`CarteIdentity.userNumber`, `CardDelivery.recipientNumber`, `CardDelivery.deliveredAt`).
- Switch entitlement `aps-environment` to production through the archive/signing flow.
- Test two iCloud accounts on two physical devices; CloudKit delivery cannot be fully validated in this Linux CI environment.

## Remaining polish after first TestFlight

- Add full PencilKit drawing canvas, thumbnail rendering, and CKAsset transit for drawings.
- Add image compression/downsampling controls for very large photo-library selections.
- Add block/report controls and sender allow-lists.
- Add UI tests and CloudKit integration tests that run on macOS/Xcode CI.

## CloudKit-first postcard composition update

Carte is officially CloudKit-first for the native iPhone app. The design follows the useful shape of `adamwulf/cloudkit-manager`: use CloudKit as a simple iCloud-backed message transit layer, verify the active iCloud account, send text plus binary assets as CloudKit records/assets, fetch new deliveries, and remove transit records after receipt. We do not vendor the Objective-C framework because the current app is Swift/SwiftUI-first and already has a typed `CardTransport` abstraction, but the CloudKit transport now mirrors the same message-plus-image pattern.

Composition now supports two editable postcard sides. Each side can contain text or a selected photo. Photos are imported from the user's photo library into Carte's local Application Support attachment directory and attached to CloudKit `Card` records as `CKAsset` values while in transit.

When a recipient taps Done in the in-tray, Carte writes the postcard to a local PDF before removing the CloudKit transit records. PDFs are saved in the user's Documents directory under `Carte Postcards`, so the files are visible through the Files app's On My iPhone storage for the app.

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

- Upload real selected photo/drawing data as `CKAsset` records while in transit, then cache the downloaded asset locally with the archive entry.
- Add full PencilKit editing canvas and thumbnail rendering.
- Add block/report controls and sender allow-lists.
- Add UI tests and CloudKit integration tests that run on macOS/Xcode CI.

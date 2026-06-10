# Carte technical plan

## Current architecture

- **iOS app:** `Carte.xcodeproj` contains a SwiftUI application target for TestFlight handoff.
- **Core package:** `CarteCore` owns card/domain invariants.
- **Feature package:** `CarteFeature` owns app state, transports, profile/contact/archive storage, CloudKit integration, and SwiftUI screens.
- **Serverless transit:** `CloudKitCardTransport` uses CloudKit only as a temporary delivery queue. Once the recipient dismisses an examined tray card, the app saves it to the local JSON archive and deletes the CloudKit transit records.
- **Local library:** `JSONProfileStore` persists `profile.json`, `contacts.json`, and `archive.json` in Application Support.

## Card lifecycle

1. Sender composes a card locally.
2. `CardTransport.send` creates a transient per-recipient delivery copy in CloudKit.
3. Recipient refreshes the Tray and examines the card.
4. Recipient taps **Done**.
5. `CarteAppState.dismissToArchive(_:)` stamps `archivedAt`, writes the card to local archive storage, and acknowledges the transit delivery by deleting it remotely.
6. Archive browsing reads from local storage only.
7. Erasing a tray card deletes the transit copy without archiving; erasing an archive card deletes the local copy only.

## CloudKit records

CloudKit stores these records only while a card is in transit.

### `CarteProfile`

- recordName: user UUID / invite code
- `displayName: String`
- `inviteCode: String`
- `createdAt: Date`

### `Card`

- recordName: transient card UUID
- `senderID: String`
- `senderDisplayName: String`
- `createdAt: Date`
- `sentAt: Date`
- `lifecycle: String`
- `sidesData: Data` JSON-encoded `[CardSide]`

### `CardDelivery`

- recordName: delivery UUID
- `cardID: String`
- `recipientID: String`
- `senderID: String`
- `deliveredAt: Date`

## Before TestFlight

- Replace placeholder bundle/container identifiers with production identifiers.
- Create CloudKit schema in Development by running the app once.
- Add indexes for delivery queries and deploy schema to Production.
- Switch entitlement `aps-environment` to production through the archive/signing flow.
- Test two iCloud accounts on two physical devices; CloudKit delivery cannot be fully validated in this Linux CI environment.

## Remaining polish after first TestFlight

- Upload real selected photo/drawing data as `CKAsset` records while in transit, then cache the downloaded asset locally with the archive entry.
- Add full PencilKit editing canvas and thumbnail rendering.
- Add block/report controls and sender allow-lists.
- Add UI tests and CloudKit integration tests that run on macOS/Xcode CI.

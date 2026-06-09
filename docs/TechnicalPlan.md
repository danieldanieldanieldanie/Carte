# Carte technical plan

## Current architecture

- **iOS app:** `Carte.xcodeproj` contains a SwiftUI application target for TestFlight handoff.
- **Core package:** `CarteCore` owns card/domain invariants.
- **Feature package:** `CarteFeature` owns app state, transports, profile/contact storage, CloudKit integration, and SwiftUI screens.
- **Serverless delivery:** `CloudKitCardTransport` uses the public CloudKit database so cards can be delivered across iCloud accounts without running a server.

## CloudKit records

### `CarteProfile`

- recordName: user UUID / invite code
- `displayName: String`
- `inviteCode: String`
- `createdAt: Date`

### `Card`

- recordName: card UUID
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
- `archivedAt: Date?`
- `erasedAt: Date?`

## Before TestFlight

- Replace placeholder bundle/container identifiers with production identifiers.
- Create CloudKit schema in Development by running the app once.
- Add indexes for delivery queries and deploy schema to Production.
- Switch entitlement `aps-environment` to production through the archive/signing flow.
- Test two iCloud accounts on two physical devices; CloudKit sharing cannot be fully validated in this Linux CI environment.

## Remaining polish after first TestFlight

- Upload real selected photo/drawing data as `CKAsset` records instead of current attachment tokens.
- Add full PencilKit editing canvas and thumbnail rendering.
- Add block/report controls and sender allow-lists.
- Add UI tests and CloudKit integration tests that run on macOS/Xcode CI.

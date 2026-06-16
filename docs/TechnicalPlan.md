# Carte technical plan

## Current target

Carte is now native iPhone only in this repository. Firebase and the web prototype have been removed. The app is designed to be opened in Xcode, pointed at a real Apple Developer team / CloudKit container, and sent to TestFlight without renting servers.

## Architecture

- `CarteCore`: domain models (`Card`, `CardSide`) and basic invariants.
- `CarteFeature`: app state, SwiftUI UI, CloudKit transport, CloudKit identity directory, local JSON stores, attachment storage, and PDF export.
- `App/CarteiOS`: app entrypoint, Info.plist, entitlements, and Xcode target.

## CloudKit record model

### `CarteIdentity`

- recordName: iCloud user record name
- `appUserID: String`
- `displayName: String`
- `userNumber: Int64`
- `createdAt: Date`

### `CarteNumberCounter`

- recordName: `global`
- `nextNumber: Int64`

### `Card`

- recordName: transient card UUID
- `senderID: String`
- `senderDisplayName: String`
- `senderNumber: Int64?`
- `createdAt: Date`
- `sentAt: Date`
- `lifecycle: String`
- `sidesData: Data` JSON-encoded `[CardSide]`
- `photoAsset_<assetID>: CKAsset` for any photo side

### `CardDelivery`

- recordName: delivery UUID
- `cardID: String`
- `recipientID: String` local app UUID fallback
- `recipientNumber: Int64` primary address
- `senderID: String`
- `deliveredAt: Date`

## Front end

The SwiftUI front end includes:

- onboarding against CloudKit/iCloud identity,
- a Write tab with front/back side switching,
- text editing on either side,
- photo-library image selection for either side,
- inline postcard preview,
- keypad addressing by Carte number,
- long-press sending to saved contacts,
- Tray and Archive grids,
- a full-screen reader with flip, Done, and Erase actions,
- Me/settings for Carte number, contacts, and the local PDF path.

## Local storage

- Profile, contacts, and archive metadata are JSON in Application Support.
- Photo attachments are cached in Application Support/Carte/Attachments.
- PDFs are written to Documents/Carte Postcards so Files / Finder can locate them.

## Before TestFlight

- Replace placeholder bundle/container identifiers with production identifiers.
- Create CloudKit schema in Development by running the app once.
- Add indexes for identity and delivery queries and deploy schema to Production (`CarteIdentity.userNumber`, `CardDelivery.recipientNumber`, `CardDelivery.deliveredAt`).
- Switch entitlement `aps-environment` to production through the archive/signing flow.
- Test two iCloud accounts on two physical devices; CloudKit delivery cannot be fully validated in this Linux CI environment.

## Remaining polish after first TestFlight

- Add image compression/downsampling controls for very large photo-library selections.
- Add block/report controls and sender allow-lists.
- Add App Store artwork / final icon set in Xcode.
- Add UI tests and CloudKit integration tests that run on macOS/Xcode CI.

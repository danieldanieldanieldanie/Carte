# Carte / Pancarte

Carte is a native Swift-first iPhone app modeled on postcards: compose a small two-sided card, address it by a Carte number, and deliver it through CloudKit. CloudKit is only the transit layer. When the recipient taps Done, Carte saves the card locally and exports a PDF into the app's Documents/`Carte Postcards` folder.

## What is implemented now

- A real iOS app shell in `Carte.xcodeproj` with a complete SwiftUI front end: onboarding, Write, Tray, Archive, and Me.
- A Swift package split into `CarteCore` domain models and `CarteFeature` app/transport/UI features.
- One- or two-sided postcard composition with easy text editing on either side and photo-library selection for either side.
- Secure iCloud-tied identities with globally assigned Carte numbers starting at 0, used as the user-facing address for sending.
- A serverless CloudKit transit layer that writes cards, photo `CKAsset` values, and per-recipient-number deliveries only while they are in transit.
- Local JSON profile/contact/archive persistence, plus local photo attachment caching.
- Local PDF export on Done, with file sharing enabled so PDFs are visible in Files / Finder under the app's Documents folder.
- Unit tests for model invariants, transit delivery, local archive persistence, attachment storage, exporter hooks, app-state validation, identity allocation, and contact persistence.

## Run the package tests

```sh
swift test
```

## Build for iPhone / TestFlight

1. Open `Carte.xcodeproj` in Xcode.
2. Set your Apple Developer Team on the `Carte` target.
3. Replace the placeholders:
   - bundle id: `com.example.Carte`
   - CloudKit container: `iCloud.com.example.Carte`
4. In Apple Developer, enable iCloud/CloudKit and Push Notifications for the app id.
5. In CloudKit Dashboard, create/deploy indexes for:
   - `CarteIdentity.userNumber`
   - `CardDelivery.recipientNumber`
   - `CardDelivery.deliveredAt`
6. Build once on a device signed into iCloud to create the development schema.
7. Deploy the CloudKit schema to Production.
8. Archive from Xcode and upload to TestFlight.

## Product posture

Carte is intentionally minimal and intimate. There is no Firebase project and no custom server to rent. CloudKit is the official no-server transit layer, inspired by the message-plus-asset pattern in `adamwulf/cloudkit-manager` but implemented directly in Swift around Carte's own typed transport. Long-term storage lives on the recipient's iPhone.

## Identity and delivery safety

Carte numbers are allocated through CloudKit from `CarteNumberCounter/global`. The first new iCloud account receives #0; the counter then advances so the next account receives #1, and so on. The counter update and `CarteIdentity` creation are committed atomically, and concurrent signups retry on CloudKit conflicts. Card sends also commit the transient `Card` plus `CardDelivery` records atomically so a recipient should not receive a delivery pointing at a missing card.

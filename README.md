# Carte / Pancarte

Carte is a Swift-first iPhone social app modeled on postcards: compose a small card, press-and-hold a contact, and send it to their in-tray. Cards can have a front and an optional back, and recipients can erase them immediately or let them move into an archive.

## What is implemented now

- A real iOS app shell in `Carte.xcodeproj` with a minimal SwiftUI tab layout: Write, Tray, Archive, and Me.
- A Swift package split into `CarteCore` domain models and `CarteFeature` app/transport/UI features.
- Card models for one- or two-sided cards with text, photo-token, and drawing-token side types.
- A serverless CloudKit transport that writes cards and per-recipient deliveries to the public CloudKit database.
- Local JSON profile/contact persistence so signup is just a display name plus exchanging invite codes.
- Minimalistic SwiftUI flows for onboarding, composing, long-press sending, tray review, card flipping, archiving, erasing, and contact management.
- Unit tests for model invariants, delivery lifecycle, app-state validation, and contact persistence.

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
   - `CardDelivery.recipientID`
   - `CardDelivery.erasedAt`
   - `CardDelivery.archivedAt`
   - `CardDelivery.deliveredAt`
6. Archive from Xcode and upload to TestFlight.

## Product posture

This is intentionally minimal and intimate. The first TestFlight path is not address-book scraping or global discovery; it is invite-code exchange between people who already know each other. That keeps signup simple and avoids rented servers.

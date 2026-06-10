# Carte / Pancarte

Carte is a Swift-first iPhone social app modeled on postcards: compose a small card, press-and-hold a contact, and send it to their in-tray. Cards can have a front and an optional back. When a recipient finishes examining a card and taps Done, Carte saves that card into the recipient's local archive and removes the transit copy.

## What is implemented now

- A real iOS app shell in `Carte.xcodeproj` with a minimal SwiftUI tab layout: Write, Tray, Archive, and Me.
- A Swift package split into `CarteCore` domain models and `CarteFeature` app/transport/UI features.
- Card models for one- or two-sided cards with text, photo-token, and drawing-token side types.
- A serverless CloudKit transit layer that writes cards and per-recipient deliveries only while they are in transit.
- Local JSON profile/contact/archive persistence, so long-term card storage lives on the recipient's device rather than in CloudKit.
- Minimalistic SwiftUI flows for onboarding, composing, long-press sending, tray review, card flipping/examining, Done-to-local-archive, erasing, and contact management.
- Unit tests for model invariants, transit delivery, local archive persistence, app-state validation, and contact persistence.

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
   - `CardDelivery.deliveredAt`
6. Archive from Xcode and upload to TestFlight.

## Product posture

Carte is intentionally minimal and intimate. CloudKit is used as a temporary delivery route, not as the user's permanent card collection. The first TestFlight path is invite-code exchange between people who already know each other, which keeps signup simple and avoids rented servers.

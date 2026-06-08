# Carte / Pancarte

Carte is a Swift-first postcard-style social app for iPhone.

## Implemented in code now
- Core postcard domain model (`Card`, `CardSide`) with validation.
- Feature models (`Contact`, `CardDelivery`) and compose helper (`CardComposer`).
- `CardTransport` abstraction with:
  - `InMemoryCardTransport` for local/dev testing.
  - `CloudKitCardTransport` for serverless iCloud-backed delivery.
- `CarteAppState` for compose/send/inbox state orchestration.
- SwiftUI `ComposePrototypeView` with press-and-hold contact send gesture.
- Unit tests for card model, transport flow, and app-state send/inbox behavior.

## CloudKit notes
`CloudKitCardTransport` uses two record types:
- `Card`
- `CardDelivery`

This keeps infra simple (no rented servers) while preserving the same transport protocol for future evolution.

# Carte Technical Plan (Swift-first)

## Why CloudKit for v1
CloudKit is the simplest approach that still gives:
- Swift-native APIs.
- Authentication via iCloud account (plus app-level identity mapping).
- Push-driven updates via subscriptions.
- No custom server to operate in v1.

This is not federated. Federation can be a later phase once product-market fit is proven.

## App stack
- iOS 18+ target.
- SwiftUI app lifecycle.
- SwiftData for local persistence/cache.
- CloudKit for sync + delivery state.
- PencilKit for drawing cards.
- PhotosPicker for images.

## Domain model
- Card
  - id, senderID, createdAt, sentAt
  - sides: [CardSide] (count 1...2)
  - lifecycle: draft, sent, received, archived, erased
- CardSide
  - sideIndex (front/back)
  - contentType: text | photo | drawing
  - payload reference (text inline, media in CKAsset)
- Delivery
  - cardID, recipientID, deliveredAt, readAt, erasedAt, archivedAt

## CloudKit records (suggested)
- `UserProfile`
- `Card`
- `CardSide`
- `CardDelivery`
- `ContactEdge`

## Sync behavior
- Sender writes Card + sides, then a CardDelivery per recipient.
- Recipient device receives subscription push for new CardDelivery.
- App fetches delta and inserts into local inbox stack.
- Erase marks erasedAt and purges local content.

## Simplicity-first auth
- App auth: Sign in with Apple -> internal user ID.
- CloudKit user record ID mapped once on first launch.
- Keep signup to <= 20 seconds.

## Milestones

### M1 (2-3 weeks)
- Compose one-sided text/photo cards.
- Contact grid.
- Long-press send.
- Inbox stack + erase.

### M2 (2-3 weeks)
- Two-sided cards.
- Drawing side via PencilKit.
- Archive auto-move job.

### M3 (2 weeks)
- Block/report.
- Delivery reliability improvements.
- Performance pass + TestFlight.

## Future federation option
If federation is required later:
- Add a Swift server (Vapor + Postgres).
- Use ActivityPub-style actor and inbox/outbox semantics.
- Keep client model unchanged; swap transport adapter.

# Carte / Pancarte

Carte is a Swift-first postcard-style social app for iPhone.

## What is implemented now
This repository now includes a **working Swift foundation** for the product:
- Core card domain model (`Card`, `CardSide`) with one/two-side validation.
- A composition helper (`CardComposer`) for text postcard drafts.
- A simple transport layer (`CardTransport`) plus in-memory implementation (`InMemoryCardTransport`) that supports:
  - send to contacts,
  - inbox retrieval,
  - erase behavior,
  - archive aging hook.
- A SwiftUI prototype compose screen (`ComposePrototypeView`) behind `canImport(SwiftUI)`.
- Unit tests for compose/send/erase flow.

## Why this approach
You asked to "just build it" with as much Swift as possible. This implementation gives you a real, testable Swift foundation without requiring backend infrastructure first.

## Next step to ship on iPhone
1. Create an Xcode iOS app target that imports `CarteFeature`.
2. Replace `InMemoryCardTransport` with CloudKit-backed transport while keeping the same `CardTransport` protocol.
3. Connect Sign in with Apple to create a local user profile.
4. Wire long-press contact send and inbox/archive screens.

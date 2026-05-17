# Carte / Pancarte

A Swift-first social iPhone app inspired by postcards.

This repository currently contains an implementation blueprint and starter Swift domain models.

## Product direction
- Compose and send postcard-like **Cards** (text, photo, or drawing).
- Optional two-sided cards (front/back).
- Minimalist skeuomorphic UI.
- Long-press contact to send.
- Inbox stack with erase/archive behavior.

## Architecture choice (simple, Swift-heavy)
- **Client:** SwiftUI + Observation + SwiftData.
- **Delivery:** **CloudKit** (private/public database + subscriptions) for near-real-time sync with APNs.
- **Auth:** Sign in with Apple (single-tap onboarding) + optional phone/email profile fields.

This avoids running custom infrastructure in v1 and keeps most development in Swift.

## Next step
Open `docs/ProductSpec.md` and `docs/TechnicalPlan.md` and implement milestone M1.

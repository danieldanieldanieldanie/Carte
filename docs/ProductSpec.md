# Carte Product Spec (v1)

## Core concept
Carte is a private social postcard app. Users create discrete "cards" and send them to contacts. Every card is a standalone object that can be viewed, kept, or erased.

## Primary flows

### 1) Compose
- Default screen is card composition canvas.
- Card can contain one medium per side:
  - Text
  - Photo
  - Drawing
- Card may have only a front side, or front + back.

### 2) Send
- Contacts appear as a grid under the composer.
- Long-pressing a contact sends the currently composed card.
- Show haptic + subtle stamped animation on send.

### 3) Receive
- Inbox presents incoming cards in a stack.
- Each card displays sender name and sent date.
- Recipient can flip card to inspect both sides.
- "Erase" button permanently deletes card for recipient.
- Non-erased cards auto-move to archive after a configurable delay (e.g., 7 days).

### 4) Archive
- Chronological gallery of preserved cards.
- Cards remain discrete immutable objects after send.

## UX principles
- Minimal controls, tactile metaphors (paper texture, shadows, stacked depth).
- No feed algorithm; purely person-to-person exchange.
- Low-friction onboarding.

## Onboarding requirements
- Sign in with Apple as the default.
- One-step display name entry.
- Optional: import contacts (permission-gated).

## Safety & trust (v1)
- Block user.
- Report user/card.
- Private by default; no public discovery unless explicitly enabled.

# Carte / Pancarte product spec

## Principle

Carte is a quiet postcard app. No feeds, likes, metrics, or algorithmic ranking. The primary action is writing one small card to one known person.

## First TestFlight scope

### Onboarding

- User enters a display name.
- App creates a local profile UUID that doubles as an invite code.
- Friends exchange invite codes manually.

### Compose

- A card has a front and optional back.
- The composer is a single paper-like surface with sparse controls.
- Text is supported directly.
- Photo and drawing sides are represented in the model/UI; full media upload is the next hardening step.
- Long-pressing a contact sends the current card.

### Receive

- Incoming cards appear in the Tray.
- A card displays the sender name and one side at a time.
- Tapping flips a two-sided card.
- Erase removes the delivery from the visible tray/archive.
- Archive saves a card outside the tray.

### Archive

- Archive is a simple chronological list of saved cards.
- Cards can still be erased from the archive.

### Visual design

- Warm off-white canvas.
- Paper cards with thin borders and subtle shadows.
- System typography with a light serif treatment on card content.
- Sparse labels and plain capsule actions.

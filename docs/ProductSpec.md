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
- Tapping flips/examines a two-sided card.
- **Done** dismisses the examined card from the Tray, stores it in the recipient's local archive, and removes the in-transit CloudKit copy.
- **Erase** removes a tray card without archiving it.

### Archive

- Archive is a local chronological list of dismissed cards.
- Archive contents are not CloudKit-backed permanent storage.
- Cards can be erased from the archive, which removes the local copy.

### Visual design

- Warm off-white canvas.
- Paper cards with thin borders and subtle shadows.
- System typography with a light serif treatment on card content.
- Sparse labels and plain capsule actions.

# Carte / Pancarte product spec

## Principle

Carte is a quiet postcard app. No feeds, likes, metrics, or algorithmic ranking. The primary action is writing one small card to one known person.

## First TestFlight scope

### Onboarding

- User enters a display name.
- App asks CloudKit for the signed-in iCloud user record and creates one persistent Carte identity for that iCloud account.
- App assigns the user a global Carte number, starting from 0 upward.
- Friends exchange Carte numbers manually.

### Compose

- A card has a front and optional back.
- The composer is a single paper-like surface with sparse controls.
- Text is supported directly.
- Text and photo-library image sides are supported in the app and sent through CloudKit as text payloads plus photo assets.
- The primary send control is a numeric keypad; entering a Carte number sends the current card.
- Long-pressing a saved contact number also sends the current card.

### Receive

- Incoming cards appear in the Tray.
- A card displays the sender name and one side at a time.
- Tapping flips/examines a two-sided card.
- **Done** dismisses the examined card from the Tray, exports a local PDF, stores archive metadata locally, and removes the in-transit CloudKit copy.
- **Erase** removes a tray card without archiving it.

### Archive

- Archive is a local chronological list of dismissed cards, backed by local metadata and PDFs in Documents/Carte Postcards.
- Archive contents are not CloudKit-backed permanent storage.
- Cards can be erased from the archive, which removes the local copy.

### Visual design

- Warm off-white canvas.
- Paper cards with thin borders and subtle shadows.
- System typography with a light serif treatment on card content.
- Sparse labels and plain capsule actions.

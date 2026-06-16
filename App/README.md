# Carte iOS target

Open `Carte.xcodeproj` in Xcode to run the native iPhone app.

## Required setup

- Replace `com.example.Carte` and `iCloud.com.example.Carte` with your real bundle and CloudKit container identifiers.
- Set your Apple Developer Team.
- Enable iCloud/CloudKit and Push Notifications for the app id.
- Run on a real iPhone signed into iCloud to validate account identity, CloudKit identity allocation, delivery, and push behavior.

## Photo and PDF behavior

The composer uses the photo-library permission string in `Info.plist` so users can place gallery photos on either side of a postcard. Received postcards are exported as PDFs to Documents/`Carte Postcards` when the recipient taps Done. `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are enabled so those files are easy to inspect through Files / Finder.

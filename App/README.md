# Carte iOS app handoff

Open `Carte.xcodeproj` in Xcode, set your Apple Developer Team, and replace the placeholder bundle/container identifiers:

- Bundle identifier: `com.example.Carte`
- CloudKit container: `iCloud.com.example.Carte`

Before TestFlight, create matching identifiers in the Apple Developer portal, enable iCloud + CloudKit + Push Notifications, and deploy the CloudKit schema from Development to Production after creating indexes for `CardDelivery.recipientID` and `CardDelivery.deliveredAt`.

CloudKit is only the transit layer. Cards move to `archive.json` on the recipient device when the recipient taps Done in the Tray, and the CloudKit delivery/card records are deleted.

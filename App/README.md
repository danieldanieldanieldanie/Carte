# Carte iOS app handoff

Open `Carte.xcodeproj` in Xcode, set your Apple Developer Team, and replace the placeholder bundle/container identifiers:

- Bundle identifier: `com.example.Carte`
- CloudKit container: `iCloud.com.example.Carte`

Before TestFlight, create matching identifiers in the Apple Developer portal, enable iCloud + CloudKit + Push Notifications, and deploy the CloudKit schema from Development to Production after creating indexes for `CardDelivery.recipientID`, `CardDelivery.erasedAt`, `CardDelivery.archivedAt`, and `CardDelivery.deliveredAt`.

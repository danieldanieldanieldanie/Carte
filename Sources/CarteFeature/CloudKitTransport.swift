import Foundation
import CarteCore

public enum CloudKitTransportError: Error, LocalizedError {
    case unsupportedPlatform
    case iCloudAccountUnavailable
    case recordDecodeFailed
    case subscriptionUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "CloudKit transport is unavailable on this platform."
        case .iCloudAccountUnavailable:
            return "Sign in to iCloud before using Carte delivery."
        case .recordDecodeFailed:
            return "Failed to decode CloudKit record payload."
        case .subscriptionUnavailable:
            return "CloudKit push subscriptions could not be configured."
        }
    }
}

#if canImport(CloudKit)
import CloudKit

public actor CloudKitCardTransport: CardTransport {
    public static let cardRecordType = "Card"
    public static let deliveryRecordType = "CardDelivery"
    public static let profileRecordType = "CarteProfile"
    public static let inboxSubscriptionIDPrefix = "CarteInbox-"

    private let container: CKContainer
    private let database: CKDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// The public database lets cards move between iCloud users without rented servers.
    /// Use a dedicated CloudKit container and indexes for `recipientNumber`, `cardID`, and `deliveredAt` before TestFlight.
    public init(container: CKContainer = .default(), scope: CKDatabase.Scope = .public) {
        self.container = container
        switch scope {
        case .private:
            self.database = container.privateCloudDatabase
        case .public:
            self.database = container.publicCloudDatabase
        case .shared:
            self.database = container.sharedCloudDatabase
        @unknown default:
            self.database = container.publicCloudDatabase
        }
    }

    public func ensureAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else { throw CloudKitTransportError.iCloudAccountUnavailable }
    }

    public func publishProfile(_ profile: UserProfile) async throws {
        try await ensureAccountAvailable()
        let record = CKRecord(recordType: Self.profileRecordType, recordID: .init(recordName: profile.id.uuidString))
        record["displayName"] = profile.displayName as CKRecordValue
        record["inviteCode"] = profile.inviteCode as CKRecordValue
        record["createdAt"] = profile.createdAt as CKRecordValue
        _ = try await database.save(record)
    }

    public func fetchProfile(inviteCode: String) async throws -> UserProfile? {
        try await ensureAccountAvailable()
        guard let id = UUID(uuidString: inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: id.uuidString))
            return try Self.decodeProfile(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    public func configureInboxPushes(for recipient: UserAddress) async throws {
        try await ensureAccountAvailable()
        let predicate = NSPredicate(format: "recipientNumber == %lld", Int64(recipient.number))
        let subscription = CKQuerySubscription(
            recordType: Self.deliveryRecordType,
            predicate: predicate,
            subscriptionID: Self.inboxSubscriptionIDPrefix + String(recipient.number),
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.alertBody = "A new Carte arrived."
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    public func send(card: Card, to recipients: [Contact]) async throws -> [CardDelivery] {
        try await ensureAccountAvailable()

        var recordsToSave: [CKRecord] = []
        var deliveries: [CardDelivery] = []
        for recipient in recipients {
            guard let recipientNumber = recipient.userNumber else { throw CarteUserFacingError.invalidUserNumber }
            let recipientID = recipient.id
            let deliveryID = UUID()
            let cardID = UUID()
            let transientCard = Card(
                id: cardID,
                senderID: card.senderID,
                senderDisplayName: card.senderDisplayName,
                createdAt: card.createdAt,
                sentAt: .now,
                sides: card.sides,
                lifecycle: .sent
            )
            let delivery = CardDelivery(id: deliveryID, card: transientCard, recipientID: recipientID, recipientNumber: recipientNumber)

            let cardRecord = CKRecord(recordType: Self.cardRecordType, recordID: .init(recordName: transientCard.id.uuidString))
            cardRecord["senderID"] = transientCard.senderID.uuidString as CKRecordValue
            cardRecord["senderDisplayName"] = transientCard.senderDisplayName as CKRecordValue
            if let senderNumber = transientCard.senderNumber {
                cardRecord["senderNumber"] = NSNumber(value: senderNumber) as CKRecordValue
            }
            cardRecord["createdAt"] = transientCard.createdAt as CKRecordValue
            if let sentAt = transientCard.sentAt {
                cardRecord["sentAt"] = sentAt as CKRecordValue
            }
            cardRecord["lifecycle"] = transientCard.lifecycle.rawValue as CKRecordValue
            cardRecord["sidesData"] = try encoder.encode(transientCard.sides) as CKRecordValue

            let deliveryRecord = CKRecord(recordType: Self.deliveryRecordType, recordID: .init(recordName: delivery.id.uuidString))
            deliveryRecord["cardID"] = transientCard.id.uuidString as CKRecordValue
            deliveryRecord["recipientID"] = recipientID.uuidString as CKRecordValue
            deliveryRecord["recipientNumber"] = NSNumber(value: recipientNumber) as CKRecordValue
            deliveryRecord["senderID"] = transientCard.senderID.uuidString as CKRecordValue
            deliveryRecord["deliveredAt"] = delivery.deliveredAt as CKRecordValue

            recordsToSave.append(cardRecord)
            recordsToSave.append(deliveryRecord)
            deliveries.append(delivery)
        }

        _ = try await database.modifyRecords(saving: recordsToSave, deleting: [])
        return deliveries
    }

    public func inbox(for recipient: UserAddress) async throws -> [CardDelivery] {
        try await ensureAccountAvailable()
        let predicate: NSPredicate
        if recipient.number >= 0 {
            predicate = NSPredicate(format: "recipientNumber == %lld", Int64(recipient.number))
        } else {
            predicate = NSPredicate(format: "recipientID == %@", recipient.id.uuidString)
        }
        let query = CKQuery(recordType: Self.deliveryRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "deliveredAt", ascending: false)]
        let matches = try await fetchAllRecords(matching: query)
        return try await decodeDeliveries(matches, fallbackRecipient: recipient)
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }

    public func archive(deliveryID: UUID, for recipient: UserAddress) async throws {
        try await erase(deliveryID: deliveryID, for: recipient)
    }

    public func erase(deliveryID: UUID, for recipient: UserAddress) async throws {
        try await ensureAccountAvailable()
        let recordID = CKRecord.ID(recordName: deliveryID.uuidString)
        let record = try await database.record(for: recordID)
        let recordRecipientID = record["recipientID"] as? String
        let recordRecipientNumber = (record["recipientNumber"] as? NSNumber).map(\.intValue)
        guard recordRecipientID == recipient.id.uuidString || recordRecipientNumber == recipient.number else { return }
        let cardRecordID = (record["cardID"] as? String).map { CKRecord.ID(recordName: $0) }
        var idsToDelete = [recordID]
        if let cardRecordID {
            idsToDelete.append(cardRecordID)
        }
        _ = try await database.modifyRecords(saving: [], deleting: idsToDelete)
    }

    public func archiveExpired(for recipient: UserAddress, olderThan: TimeInterval) async throws {
        // Expiry is handled locally after the card is saved; CloudKit only holds transient deliveries.
    }

    private func fetchAllRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        let firstPage = try await database.records(matching: query, resultsLimit: CKQueryOperation.maximumResults)
        try append(firstPage.matchResults, to: &records)
        var cursor = firstPage.queryCursor
        while let nextCursor = cursor {
            let page = try await database.records(continuingMatchFrom: nextCursor, resultsLimit: CKQueryOperation.maximumResults)
            try append(page.matchResults, to: &records)
            cursor = page.queryCursor
        }
        return records
    }

    private func append(_ results: [(CKRecord.ID, Result<CKRecord, Error>)], to records: inout [CKRecord]) throws {
        for (_, result) in results {
            records.append(try result.get())
        }
    }

    private func decodeDeliveries(_ records: [CKRecord], fallbackRecipient: UserAddress) async throws -> [CardDelivery] {
        var deliveries: [CardDelivery] = []
        for deliveryRecord in records {
            guard
                let cardIDRaw = deliveryRecord["cardID"] as? String,
                let cardID = UUID(uuidString: cardIDRaw),
                let deliveredAt = deliveryRecord["deliveredAt"] as? Date
            else {
                throw CloudKitTransportError.recordDecodeFailed
            }

            let cardRecord = try await database.record(for: CKRecord.ID(recordName: cardID.uuidString))
            let card = try Self.decodeCard(from: cardRecord)
            deliveries.append(
                CardDelivery(
                    id: UUID(uuidString: deliveryRecord.recordID.recordName) ?? UUID(),
                    card: card,
                    recipientID: UUID(uuidString: deliveryRecord["recipientID"] as? String ?? "") ?? fallbackRecipient.id,
                    recipientNumber: (deliveryRecord["recipientNumber"] as? NSNumber).map(\.intValue) ?? (fallbackRecipient.number >= 0 ? fallbackRecipient.number : nil),
                    deliveredAt: deliveredAt,
                    erasedAt: deliveryRecord["erasedAt"] as? Date,
                    archivedAt: deliveryRecord["archivedAt"] as? Date
                )
            )
        }
        return deliveries
    }

    private static func decodeProfile(from record: CKRecord) throws -> UserProfile {
        guard
            let displayName = record["displayName"] as? String,
            let inviteCode = record["inviteCode"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let id = UUID(uuidString: record.recordID.recordName)
        else {
            throw CloudKitTransportError.recordDecodeFailed
        }
        return UserProfile(id: id, displayName: displayName, inviteCode: inviteCode, createdAt: createdAt)
    }

    private static func decodeCard(from record: CKRecord) throws -> Card {
        guard
            let senderIDRaw = record["senderID"] as? String,
            let senderID = UUID(uuidString: senderIDRaw),
            let senderDisplayName = record["senderDisplayName"] as? String,
            let createdAt = record["createdAt"] as? Date,
            let lifecycleRaw = record["lifecycle"] as? String,
            let lifecycle = Card.Lifecycle(rawValue: lifecycleRaw),
            let sidesData = record["sidesData"] as? Data
        else {
            throw CloudKitTransportError.recordDecodeFailed
        }

        let sides = try JSONDecoder().decode([CardSide].self, from: sidesData)
        return Card(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            senderID: senderID,
            senderDisplayName: senderDisplayName,
            senderNumber: (record["senderNumber"] as? NSNumber).map(\.intValue),
            createdAt: createdAt,
            sentAt: record["sentAt"] as? Date,
            sides: sides,
            lifecycle: lifecycle
        )
    }
}
#else
public actor CloudKitCardTransport: CardTransport {
    public init() {}

    public func send(card: Card, to recipients: [Contact]) async throws -> [CardDelivery] {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func inbox(for recipient: UserAddress) async throws -> [CardDelivery] {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func archive(deliveryID: UUID, for recipient: UserAddress) async throws {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func erase(deliveryID: UUID, for recipient: UserAddress) async throws {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func archiveExpired(for recipient: UserAddress, olderThan: TimeInterval) async throws {
        throw CloudKitTransportError.unsupportedPlatform
    }
}
#endif

import Foundation
import CarteCore

public enum CloudKitTransportError: Error, LocalizedError {
    case unsupportedPlatform
    case recordDecodeFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "CloudKit transport is unavailable on this platform."
        case .recordDecodeFailed:
            return "Failed to decode CloudKit record payload."
        }
    }
}

#if canImport(CloudKit)
import CloudKit

public actor CloudKitCardTransport: CardTransport {
    private let database: CKDatabase

    public init(container: CKContainer = .default(), scope: CKDatabase.Scope = .private) {
        switch scope {
        case .private:
            self.database = container.privateCloudDatabase
        case .public:
            self.database = container.publicCloudDatabase
        case .shared:
            self.database = container.sharedCloudDatabase
        @unknown default:
            self.database = container.privateCloudDatabase
        }
    }

    public func send(card: Card, to recipientIDs: [UUID]) async throws -> [CardDelivery] {
        let sentCard = Card(
            id: card.id,
            senderID: card.senderID,
            senderDisplayName: card.senderDisplayName,
            createdAt: card.createdAt,
            sentAt: .now,
            sides: card.sides,
            lifecycle: .sent
        )

        let cardRecord = CKRecord(recordType: "Card", recordID: .init(recordName: sentCard.id.uuidString))
        cardRecord["senderID"] = sentCard.senderID.uuidString as CKRecordValue
        cardRecord["senderDisplayName"] = sentCard.senderDisplayName as CKRecordValue
        cardRecord["createdAt"] = sentCard.createdAt as CKRecordValue
        if let sentAt = sentCard.sentAt {
            cardRecord["sentAt"] = sentAt as CKRecordValue
        }
        cardRecord["lifecycle"] = sentCard.lifecycle.rawValue as CKRecordValue
        cardRecord["sidesData"] = try JSONEncoder().encode(sentCard.sides) as CKRecordValue

        _ = try await database.save(cardRecord)

        var deliveries: [CardDelivery] = []
        for recipientID in recipientIDs {
            let delivery = CardDelivery(card: sentCard, recipientID: recipientID)
            let record = CKRecord(recordType: "CardDelivery", recordID: .init(recordName: delivery.id.uuidString))
            record["cardID"] = sentCard.id.uuidString as CKRecordValue
            record["recipientID"] = recipientID.uuidString as CKRecordValue
            record["deliveredAt"] = delivery.deliveredAt as CKRecordValue
            _ = try await database.save(record)
            deliveries.append(delivery)
        }

        return deliveries
    }

    public func inbox(for recipientID: UUID) async throws -> [CardDelivery] {
        let predicate = NSPredicate(format: "recipientID == %@", recipientID.uuidString)
        let query = CKQuery(recordType: "CardDelivery", predicate: predicate)

        let (matchResults, _) = try await database.records(matching: query)

        var deliveries: [CardDelivery] = []
        for (_, result) in matchResults {
            let deliveryRecord = try result.get()
            guard
                let cardIDRaw = deliveryRecord["cardID"] as? String,
                let cardID = UUID(uuidString: cardIDRaw),
                let deliveredAt = deliveryRecord["deliveredAt"] as? Date
            else {
                throw CloudKitTransportError.recordDecodeFailed
            }

            let cardRecord = try await database.record(for: CKRecord.ID(recordName: cardID.uuidString))
            let card = try Self.decodeCard(from: cardRecord)

            let erasedAt = deliveryRecord["erasedAt"] as? Date
            let archivedAt = deliveryRecord["archivedAt"] as? Date

            deliveries.append(
                CardDelivery(
                    id: UUID(uuidString: deliveryRecord.recordID.recordName) ?? UUID(),
                    card: card,
                    recipientID: recipientID,
                    deliveredAt: deliveredAt,
                    erasedAt: erasedAt,
                    archivedAt: archivedAt
                )
            )
        }

        return deliveries
            .filter(\.isInInbox)
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }

    public func erase(deliveryID: UUID, for recipientID: UUID) async throws {
        let recordID = CKRecord.ID(recordName: deliveryID.uuidString)
        let record = try await database.record(for: recordID)
        guard (record["recipientID"] as? String) == recipientID.uuidString else { return }
        record["erasedAt"] = Date() as CKRecordValue
        _ = try await database.save(record)
    }

    public func archiveExpired(for recipientID: UUID, olderThan: TimeInterval) async throws {
        let all = try await inboxIncludingArchived(for: recipientID)
        let now = Date()
        for delivery in all where delivery.erasedAt == nil && delivery.archivedAt == nil {
            guard now.timeIntervalSince(delivery.deliveredAt) >= olderThan else { continue }
            let recordID = CKRecord.ID(recordName: delivery.id.uuidString)
            let record = try await database.record(for: recordID)
            record["archivedAt"] = now as CKRecordValue
            _ = try await database.save(record)
        }
    }

    private func inboxIncludingArchived(for recipientID: UUID) async throws -> [CardDelivery] {
        let predicate = NSPredicate(format: "recipientID == %@", recipientID.uuidString)
        let query = CKQuery(recordType: "CardDelivery", predicate: predicate)
        let (matches, _) = try await database.records(matching: query)

        var items: [CardDelivery] = []
        for (_, result) in matches {
            let record = try result.get()
            guard
                let cardIDRaw = record["cardID"] as? String,
                let cardID = UUID(uuidString: cardIDRaw),
                let deliveredAt = record["deliveredAt"] as? Date
            else { continue }
            let cardRecord = try await database.record(for: CKRecord.ID(recordName: cardID.uuidString))
            let card = try Self.decodeCard(from: cardRecord)
            items.append(
                CardDelivery(
                    id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
                    card: card,
                    recipientID: recipientID,
                    deliveredAt: deliveredAt,
                    erasedAt: record["erasedAt"] as? Date,
                    archivedAt: record["archivedAt"] as? Date
                )
            )
        }

        return items
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

    public func send(card: Card, to recipientIDs: [UUID]) async throws -> [CardDelivery] {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func inbox(for recipientID: UUID) async throws -> [CardDelivery] {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func erase(deliveryID: UUID, for recipientID: UUID) async throws {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func archiveExpired(for recipientID: UUID, olderThan: TimeInterval) async throws {
        throw CloudKitTransportError.unsupportedPlatform
    }
}
#endif

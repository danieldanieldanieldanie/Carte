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
    /// Use a dedicated CloudKit container and indexes for `recipientID`, `cardID`, and `erasedAt` before TestFlight.
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

    public func configureInboxPushes(for recipientID: UUID) async throws {
        try await ensureAccountAvailable()
        let predicate = NSPredicate(format: "recipientID == %@ AND erasedAt == nil", recipientID.uuidString)
        let subscription = CKQuerySubscription(
            recordType: Self.deliveryRecordType,
            predicate: predicate,
            subscriptionID: Self.inboxSubscriptionIDPrefix + recipientID.uuidString,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate]
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        info.alertBody = "A new Carte arrived."
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    public func send(card: Card, to recipientIDs: [UUID]) async throws -> [CardDelivery] {
        try await ensureAccountAvailable()
        let sentCard = Card(
            id: card.id,
            senderID: card.senderID,
            senderDisplayName: card.senderDisplayName,
            createdAt: card.createdAt,
            sentAt: .now,
            sides: card.sides,
            lifecycle: .sent
        )

        let cardRecord = CKRecord(recordType: Self.cardRecordType, recordID: .init(recordName: sentCard.id.uuidString))
        cardRecord["senderID"] = sentCard.senderID.uuidString as CKRecordValue
        cardRecord["senderDisplayName"] = sentCard.senderDisplayName as CKRecordValue
        cardRecord["createdAt"] = sentCard.createdAt as CKRecordValue
        if let sentAt = sentCard.sentAt {
            cardRecord["sentAt"] = sentAt as CKRecordValue
        }
        cardRecord["lifecycle"] = sentCard.lifecycle.rawValue as CKRecordValue
        cardRecord["sidesData"] = try encoder.encode(sentCard.sides) as CKRecordValue

        var recordsToSave: [CKRecord] = [cardRecord]
        var deliveries: [CardDelivery] = []
        for recipientID in recipientIDs {
            let delivery = CardDelivery(card: sentCard, recipientID: recipientID)
            let record = CKRecord(recordType: Self.deliveryRecordType, recordID: .init(recordName: delivery.id.uuidString))
            record["cardID"] = sentCard.id.uuidString as CKRecordValue
            record["recipientID"] = recipientID.uuidString as CKRecordValue
            record["senderID"] = sentCard.senderID.uuidString as CKRecordValue
            record["deliveredAt"] = delivery.deliveredAt as CKRecordValue
            recordsToSave.append(record)
            deliveries.append(delivery)
        }

        _ = try await database.modifyRecords(saving: recordsToSave, deleting: [])
        return deliveries
    }

    public func inbox(for recipientID: UUID) async throws -> [CardDelivery] {
        try await ensureAccountAvailable()
        let predicate = NSPredicate(format: "recipientID == %@ AND erasedAt == nil", recipientID.uuidString)
        let query = CKQuery(recordType: Self.deliveryRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "deliveredAt", ascending: false)]
        let matches = try await fetchAllRecords(matching: query)
        return try await decodeDeliveries(matches, recipientID: recipientID)
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }

    public func archive(deliveryID: UUID, for recipientID: UUID) async throws {
        try await updateDelivery(deliveryID: deliveryID, recipientID: recipientID) { record in
            record["archivedAt"] = Date() as CKRecordValue
        }
    }

    public func erase(deliveryID: UUID, for recipientID: UUID) async throws {
        try await updateDelivery(deliveryID: deliveryID, recipientID: recipientID) { record in
            record["erasedAt"] = Date() as CKRecordValue
        }
    }

    public func archiveExpired(for recipientID: UUID, olderThan: TimeInterval) async throws {
        let all = try await inbox(for: recipientID)
        let now = Date()
        for delivery in all where delivery.erasedAt == nil && delivery.archivedAt == nil {
            guard now.timeIntervalSince(delivery.deliveredAt) >= olderThan else { continue }
            try await archive(deliveryID: delivery.id, for: recipientID)
        }
    }

    private func updateDelivery(deliveryID: UUID, recipientID: UUID, mutate: (CKRecord) -> Void) async throws {
        try await ensureAccountAvailable()
        let record = try await database.record(for: CKRecord.ID(recordName: deliveryID.uuidString))
        guard (record["recipientID"] as? String) == recipientID.uuidString else { return }
        mutate(record)
        _ = try await database.save(record)
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

    private func decodeDeliveries(_ records: [CKRecord], recipientID: UUID) async throws -> [CardDelivery] {
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
                    recipientID: recipientID,
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

    public func archive(deliveryID: UUID, for recipientID: UUID) async throws {
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

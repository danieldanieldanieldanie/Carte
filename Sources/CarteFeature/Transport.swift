import Foundation
import CarteCore

public protocol CardTransport: Sendable {
    func send(card: Card, to recipientIDs: [UUID]) async throws -> [CardDelivery]
    func inbox(for recipientID: UUID) async throws -> [CardDelivery]
    func archive(deliveryID: UUID, for recipientID: UUID) async throws
    func erase(deliveryID: UUID, for recipientID: UUID) async throws
    func archiveExpired(for recipientID: UUID, olderThan: TimeInterval) async throws
}

public actor InMemoryCardTransport: CardTransport {
    private var deliveries: [UUID: [CardDelivery]] = [:]

    public init() {}

    public func send(card: Card, to recipientIDs: [UUID]) async throws -> [CardDelivery] {
        let stamped = Card(
            id: card.id,
            senderID: card.senderID,
            senderDisplayName: card.senderDisplayName,
            createdAt: card.createdAt,
            sentAt: .now,
            sides: card.sides,
            lifecycle: .sent
        )

        let created = recipientIDs.map { recipientID in
            CardDelivery(card: stamped, recipientID: recipientID)
        }

        for delivery in created {
            deliveries[delivery.recipientID, default: []].insert(delivery, at: 0)
        }
        return created
    }

    public func inbox(for recipientID: UUID) async throws -> [CardDelivery] {
        deliveries[recipientID, default: []]
    }

    public func archive(deliveryID: UUID, for recipientID: UUID) async throws {
        try await erase(deliveryID: deliveryID, for: recipientID)
    }

    public func erase(deliveryID: UUID, for recipientID: UUID) async throws {
        guard var entries = deliveries[recipientID] else { return }
        entries.removeAll { $0.id == deliveryID }
        deliveries[recipientID] = entries
    }

    public func archiveExpired(for recipientID: UUID, olderThan: TimeInterval) async throws {
        // Expiry is a local-library concern now; transports only hold cards while they are in transit.
    }
}

import Foundation
import CarteCore

public protocol CardTransport: Sendable {
    func send(card: Card, to recipientIDs: [UUID]) async throws -> [CardDelivery]
    func inbox(for recipientID: UUID) async throws -> [CardDelivery]
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
        deliveries[recipientID, default: []].filter(\.isInInbox)
    }

    public func erase(deliveryID: UUID, for recipientID: UUID) async throws {
        guard var entries = deliveries[recipientID] else { return }
        guard let idx = entries.firstIndex(where: { $0.id == deliveryID }) else { return }
        entries[idx].erasedAt = .now
        deliveries[recipientID] = entries
    }

    public func archiveExpired(for recipientID: UUID, olderThan: TimeInterval) async throws {
        guard var entries = deliveries[recipientID] else { return }
        let now = Date()
        entries = entries.map { delivery in
            guard delivery.erasedAt == nil, delivery.archivedAt == nil else { return delivery }
            let age = now.timeIntervalSince(delivery.deliveredAt)
            guard age >= olderThan else { return delivery }
            var updated = delivery
            updated.archivedAt = now
            return updated
        }
        deliveries[recipientID] = entries
    }
}

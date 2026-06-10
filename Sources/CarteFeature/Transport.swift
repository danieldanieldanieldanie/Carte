import Foundation
import CarteCore

public protocol CardTransport: Sendable {
    func send(card: Card, to recipients: [Contact]) async throws -> [CardDelivery]
    func inbox(for recipient: UserAddress) async throws -> [CardDelivery]
    func archive(deliveryID: UUID, for recipient: UserAddress) async throws
    func erase(deliveryID: UUID, for recipient: UserAddress) async throws
    func archiveExpired(for recipient: UserAddress, olderThan: TimeInterval) async throws
}

public actor InMemoryCardTransport: CardTransport {
    private var deliveries: [UUID: [CardDelivery]] = [:]
    private var deliveriesByNumber: [Int: [CardDelivery]] = [:]

    public init() {}

    public func send(card: Card, to recipients: [Contact]) async throws -> [CardDelivery] {
        let stamped = Card(
            id: card.id,
            senderID: card.senderID,
            senderDisplayName: card.senderDisplayName,
            senderNumber: card.senderNumber,
            createdAt: card.createdAt,
            sentAt: .now,
            sides: card.sides,
            lifecycle: .sent
        )

        let created = recipients.map { recipient in
            CardDelivery(card: stamped, recipientID: recipient.id, recipientNumber: recipient.userNumber)
        }

        for delivery in created {
            deliveries[delivery.recipientID, default: []].insert(delivery, at: 0)
            if let recipientNumber = delivery.recipientNumber {
                deliveriesByNumber[recipientNumber, default: []].insert(delivery, at: 0)
            }
        }
        return created
    }

    public func inbox(for recipient: UserAddress) async throws -> [CardDelivery] {
        if recipient.number >= 0 {
            return deliveriesByNumber[recipient.number, default: []]
        }
        return deliveries[recipient.id, default: []]
    }

    public func archive(deliveryID: UUID, for recipient: UserAddress) async throws {
        try await erase(deliveryID: deliveryID, for: recipient)
    }

    public func erase(deliveryID: UUID, for recipient: UserAddress) async throws {
        deliveries[recipient.id, default: []].removeAll { $0.id == deliveryID }
        if recipient.number >= 0 {
            deliveriesByNumber[recipient.number, default: []].removeAll { $0.id == deliveryID }
        }
    }

    public func archiveExpired(for recipient: UserAddress, olderThan: TimeInterval) async throws {
        // Expiry is a local-library concern now; transports only hold cards while they are in transit.
    }
}

import Foundation
import CarteCore

public struct Contact: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var displayName: String

    public init(id: UUID = UUID(), displayName: String) {
        self.id = id
        self.displayName = displayName
    }
}

public struct CardDelivery: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let card: Card
    public let recipientID: UUID
    public let deliveredAt: Date
    public var erasedAt: Date?
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        card: Card,
        recipientID: UUID,
        deliveredAt: Date = .now,
        erasedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.card = card
        self.recipientID = recipientID
        self.deliveredAt = deliveredAt
        self.erasedAt = erasedAt
        self.archivedAt = archivedAt
    }

    public var isInInbox: Bool {
        erasedAt == nil && archivedAt == nil
    }
}

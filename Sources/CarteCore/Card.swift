import Foundation

public struct Card: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let senderID: UUID
    public let createdAt: Date
    public var sentAt: Date?
    public var sides: [CardSide]
    public var lifecycle: Lifecycle

    public init(
        id: UUID = UUID(),
        senderID: UUID,
        createdAt: Date = .now,
        sentAt: Date? = nil,
        sides: [CardSide],
        lifecycle: Lifecycle = .draft
    ) {
        precondition((1...2).contains(sides.count), "A card must have one or two sides.")
        self.id = id
        self.senderID = senderID
        self.createdAt = createdAt
        self.sentAt = sentAt
        self.sides = sides
        self.lifecycle = lifecycle
    }
}

public extension Card {
    enum Lifecycle: String, Codable, Sendable {
        case draft
        case sent
        case received
        case archived
        case erased
    }
}

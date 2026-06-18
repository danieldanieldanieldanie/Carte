import Foundation

public struct Card: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let senderID: UUID
    public let senderDisplayName: String
    public let senderNumber: Int?
    public let createdAt: Date
    public var sentAt: Date?
    public var sides: [CardSide]
    public var lifecycle: Lifecycle

    public init(
        id: UUID = UUID(),
        senderID: UUID,
        senderDisplayName: String,
        senderNumber: Int? = nil,
        createdAt: Date = .now,
        sentAt: Date? = nil,
        sides: [CardSide],
        lifecycle: Lifecycle = .draft
    ) {
        precondition((1...2).contains(sides.count), "A card must have one or two sides.")
        precondition(sides.map(\.index).count == Set(sides.map(\.index)).count, "A card cannot contain duplicate side indexes.")
        self.id = id
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.senderNumber = senderNumber
        self.createdAt = createdAt
        self.sentAt = sentAt
        self.sides = sides.sorted(by: { $0.index.rawValue < $1.index.rawValue })
        self.lifecycle = lifecycle
    }

    public var hasBackSide: Bool {
        sides.contains(where: { $0.index == .back })
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

    static func draftText(senderID: UUID, senderDisplayName: String, senderNumber: Int? = nil, text: String) -> Card {
        Card(
            senderID: senderID,
            senderDisplayName: senderDisplayName,
            senderNumber: senderNumber,
            sides: [.init(index: .front, content: .text(text))],
            lifecycle: .draft
        )
    }
}

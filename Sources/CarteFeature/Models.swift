import Foundation
import CarteCore

public struct Contact: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var displayName: String
    public var note: String?

    public init(id: UUID = UUID(), displayName: String, note: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.note = note
    }
}

public struct UserProfile: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var displayName: String
    public var inviteCode: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        inviteCode: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.inviteCode = inviteCode ?? id.uuidString
        self.createdAt = createdAt
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

    public var isArchived: Bool {
        erasedAt == nil && archivedAt != nil
    }
}

public enum CarteUserFacingError: Error, LocalizedError, Sendable {
    case emptyDraft
    case invalidInviteCode
    case missingProfile

    public var errorDescription: String? {
        switch self {
        case .emptyDraft:
            return "Write, draw, or add a picture before sending."
        case .invalidInviteCode:
            return "That invite code does not look like a Carte code."
        case .missingProfile:
            return "Create your Carte profile before sending cards."
        }
    }
}

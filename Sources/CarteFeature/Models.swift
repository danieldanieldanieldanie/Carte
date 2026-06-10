import Foundation
import CarteCore

public struct UserAddress: Hashable, Sendable, Codable {
    public let id: UUID
    public let number: Int

    public init(id: UUID, number: Int) {
        self.id = id
        self.number = number
    }
}

public struct Contact: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var displayName: String
    public var userNumber: Int?
    public var note: String?

    public init(id: UUID = UUID(), displayName: String, userNumber: Int? = nil, note: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.userNumber = userNumber
        self.note = note
    }

    public var address: UserAddress? {
        guard let userNumber else { return nil }
        return UserAddress(id: id, number: userNumber)
    }
}

public struct UserProfile: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var displayName: String
    public var inviteCode: String
    public var userNumber: Int?
    public var iCloudUserRecordName: String?
    public var secureIdentityVersion: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        inviteCode: String? = nil,
        userNumber: Int? = nil,
        iCloudUserRecordName: String? = nil,
        secureIdentityVersion: Int = 1,
        createdAt: Date = .now
    ) {
        self.id = id
        self.displayName = displayName
        self.inviteCode = inviteCode ?? id.uuidString
        self.userNumber = userNumber
        self.iCloudUserRecordName = iCloudUserRecordName
        self.secureIdentityVersion = secureIdentityVersion
        self.createdAt = createdAt
    }

    public var address: UserAddress? {
        guard let userNumber else { return nil }
        return UserAddress(id: id, number: userNumber)
    }
}

public struct CardDelivery: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let card: Card
    public let recipientID: UUID
    public var recipientNumber: Int?
    public let deliveredAt: Date
    public var erasedAt: Date?
    public var archivedAt: Date?

    public init(
        id: UUID = UUID(),
        card: Card,
        recipientID: UUID,
        recipientNumber: Int? = nil,
        deliveredAt: Date = .now,
        erasedAt: Date? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.card = card
        self.recipientID = recipientID
        self.recipientNumber = recipientNumber
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
    case invalidUserNumber
    case missingProfile
    case missingSecureIdentity
    case recipientNotFound(Int)

    public var errorDescription: String? {
        switch self {
        case .emptyDraft:
            return "Write, draw, or add a picture before sending."
        case .invalidInviteCode:
            return "That invite code does not look like a Carte code."
        case .invalidUserNumber:
            return "Enter a valid Carte number."
        case .missingProfile:
            return "Create your Carte profile before sending cards."
        case .missingSecureIdentity:
            return "Sign in to iCloud so Carte can create your secure identity."
        case .recipientNotFound(let number):
            return "No Carte user was found for #\(number)."
        }
    }
}

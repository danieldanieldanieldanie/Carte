import Foundation
import CarteCore

public struct ComposeDraft: Sendable {
    public var frontText: String
    public var backText: String

    public init(frontText: String = "", backText: String = "") {
        self.frontText = frontText
        self.backText = backText
    }
}

@MainActor
public final class CarteAppState {
    public var draft = ComposeDraft()
    public var contacts: [Contact]
    public private(set) var inbox: [CardDelivery] = []
    public private(set) var archive: [CardDelivery] = []

    private let transport: any CardTransport
    private let composer = CardComposer()

    public let currentUserID: UUID
    public let currentUserDisplayName: String

    public init(
        currentUserID: UUID,
        currentUserDisplayName: String,
        contacts: [Contact],
        transport: any CardTransport
    ) {
        self.currentUserID = currentUserID
        self.currentUserDisplayName = currentUserDisplayName
        self.contacts = contacts
        self.transport = transport
    }

    public func sendDraft(to contact: Contact) async throws {
        let back = draft.backText.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = composer.composeText(
            senderID: currentUserID,
            senderDisplayName: currentUserDisplayName,
            text: draft.frontText,
            back: back.isEmpty ? nil : back
        )
        _ = try await transport.send(card: card, to: [contact.id])
        draft = ComposeDraft()
    }

    public func refreshInbox() async throws {
        let all = try await transport.inbox(for: currentUserID)
        inbox = all.sorted(by: { $0.deliveredAt > $1.deliveredAt })
    }

    public func erase(_ delivery: CardDelivery) async throws {
        try await transport.erase(deliveryID: delivery.id, for: currentUserID)
        try await refreshInbox()
    }
}

import Foundation
import CarteCore
#if canImport(Combine)
import Combine
#endif

public struct ComposeDraft: Sendable, Equatable {
    public var frontText: String
    public var backText: String
    public var frontAttachmentID: String?
    public var backAttachmentID: String?
    public var frontAttachmentKind: AttachmentKind?
    public var backAttachmentKind: AttachmentKind?

    public init(
        frontText: String = "",
        backText: String = "",
        frontAttachmentID: String? = nil,
        backAttachmentID: String? = nil,
        frontAttachmentKind: AttachmentKind? = nil,
        backAttachmentKind: AttachmentKind? = nil
    ) {
        self.frontText = frontText
        self.backText = backText
        self.frontAttachmentID = frontAttachmentID
        self.backAttachmentID = backAttachmentID
        self.frontAttachmentKind = frontAttachmentKind
        self.backAttachmentKind = backAttachmentKind
    }

    public enum AttachmentKind: String, Sendable, Codable {
        case photo
        case drawing
    }

    public var isEmpty: Bool {
        frontText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && frontAttachmentID == nil
    }
}

@MainActor
public final class CarteAppState {
    #if canImport(Combine)
    public let objectWillChange = ObservableObjectPublisher()
    #endif

    public private(set) var profile: UserProfile?
    public var draft = ComposeDraft() { didSet { announceChange() } }
    public private(set) var contacts: [Contact]
    public private(set) var inbox: [CardDelivery] = []
    public private(set) var archive: [CardDelivery] = []
    public private(set) var isBusy = false
    public private(set) var statusMessage: String?

    private let transport: any CardTransport
    private let store: (any ProfileStore)?
    private let composer = CardComposer()
    private let contactBook: ContactBook?

    public var currentUserID: UUID { profile?.id ?? fallbackUserID }
    public var currentUserDisplayName: String { profile?.displayName ?? fallbackDisplayName }

    private let fallbackUserID: UUID
    private let fallbackDisplayName: String

    public init(
        currentUserID: UUID,
        currentUserDisplayName: String,
        contacts: [Contact],
        transport: any CardTransport
    ) {
        self.profile = UserProfile(id: currentUserID, displayName: currentUserDisplayName)
        self.contacts = contacts
        self.transport = transport
        self.store = nil
        self.contactBook = nil
        self.fallbackUserID = currentUserID
        self.fallbackDisplayName = currentUserDisplayName
    }

    public init(
        profile: UserProfile? = nil,
        contacts: [Contact] = [],
        transport: any CardTransport,
        store: (any ProfileStore)? = nil
    ) {
        self.profile = profile
        self.contacts = contacts
        self.transport = transport
        self.store = store
        self.contactBook = store.map(ContactBook.init(store:))
        self.fallbackUserID = profile?.id ?? UUID()
        self.fallbackDisplayName = profile?.displayName ?? "Carte User"
    }

    public func bootstrap() async {
        guard let store else { return }
        await runBusyOperation(successMessage: nil) {
            profile = try await store.loadProfile() ?? profile
            contacts = try await store.loadContacts()
            try await refreshInboxAndArchive()
        }
    }

    public func createProfile(displayName: String) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = UserProfile(displayName: trimmed.isEmpty ? "Carte User" : trimmed)
        announceChange()
        profile = next
        try await store?.saveProfile(next)
        statusMessage = "Profile ready. Share your invite code with a friend."
    }

    public func addContact(displayName: String, inviteCode: String) async throws {
        guard let contactBook else { return }
        announceChange()
        contacts = try await contactBook.addContact(displayName: displayName, inviteCode: inviteCode, to: contacts)
        statusMessage = "Contact added."
    }

    public func removeContact(_ contact: Contact) async throws {
        guard let contactBook else { return }
        announceChange()
        contacts = try await contactBook.removeContact(contact, from: contacts)
        statusMessage = "Contact removed."
    }

    public func sendDraft(to contact: Contact) async throws {
        guard let profile else { throw CarteUserFacingError.missingProfile }
        guard !draft.isEmpty else { throw CarteUserFacingError.emptyDraft }

        let card = composer.compose(
            senderID: profile.id,
            senderDisplayName: profile.displayName,
            front: content(text: draft.frontText, attachmentID: draft.frontAttachmentID, kind: draft.frontAttachmentKind),
            back: optionalBackContent()
        )
        _ = try await transport.send(card: card, to: [contact.id])
        announceChange()
        draft = ComposeDraft()
        statusMessage = "Sent to \(contact.displayName)."
    }

    public func refreshInbox() async throws {
        let all = try await transport.inbox(for: currentUserID)
        announceChange()
        inbox = all.sorted(by: { $0.deliveredAt > $1.deliveredAt })
    }

    public func refreshInboxAndArchive() async throws {
        try await transport.archiveExpired(for: currentUserID, olderThan: 24 * 60 * 60)
        let all = try await transport.inbox(for: currentUserID)
        announceChange()
        inbox = all.filter(\.isInInbox).sorted(by: { $0.deliveredAt > $1.deliveredAt })
        archive = all.filter(\.isArchived).sorted(by: { $0.deliveredAt > $1.deliveredAt })
    }

    public func erase(_ delivery: CardDelivery) async throws {
        try await transport.erase(deliveryID: delivery.id, for: currentUserID)
        try await refreshInboxAndArchive()
        announceChange()
        statusMessage = "Card erased."
    }

    public func archiveNow(_ delivery: CardDelivery) async throws {
        try await transport.archive(deliveryID: delivery.id, for: currentUserID)
        try await refreshInboxAndArchive()
    }

    public func setStatusMessage(_ message: String?) {
        announceChange()
        statusMessage = message
    }

    public func runBusyOperation(successMessage: String? = nil, _ operation: () async throws -> Void) async {
        announceChange()
        isBusy = true
        defer {
            isBusy = false
            announceChange()
        }

        do {
            try await operation()
            if let successMessage {
                statusMessage = successMessage
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func content(text: String, attachmentID: String?, kind: ComposeDraft.AttachmentKind?) -> CardSide.Content {
        if let attachmentID, let kind {
            switch kind {
            case .photo:
                return .photo(assetID: attachmentID)
            case .drawing:
                return .drawing(assetID: attachmentID)
            }
        }
        return .text(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func optionalBackContent() -> CardSide.Content? {
        let trimmed = draft.backText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || draft.backAttachmentID != nil else { return nil }
        return content(text: trimmed, attachmentID: draft.backAttachmentID, kind: draft.backAttachmentKind)
    }

    private func announceChange() {
        #if canImport(Combine)
        objectWillChange.send()
        #endif
    }
}

#if canImport(Combine)
extension CarteAppState: ObservableObject {}
#endif

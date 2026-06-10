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
    private let identityDirectory: (any IdentityDirectory)?
    private let composer = CardComposer()
    private let contactBook: ContactBook?

    public var currentUserID: UUID { profile?.id ?? fallbackUserID }
    public var currentUserNumber: Int? { profile?.userNumber }
    public var currentUserDisplayName: String { profile?.displayName ?? fallbackDisplayName }

    private var currentUserAddress: UserAddress {
        UserAddress(id: currentUserID, number: currentUserNumber ?? -1)
    }

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
        self.identityDirectory = nil
        self.contactBook = nil
        self.fallbackUserID = currentUserID
        self.fallbackDisplayName = currentUserDisplayName
    }

    public init(
        profile: UserProfile? = nil,
        contacts: [Contact] = [],
        transport: any CardTransport,
        store: (any ProfileStore)? = nil,
        identityDirectory: (any IdentityDirectory)? = nil
    ) {
        self.profile = profile
        self.contacts = contacts
        self.transport = transport
        self.store = store
        self.identityDirectory = identityDirectory
        self.contactBook = store.map(ContactBook.init(store:))
        self.fallbackUserID = profile?.id ?? UUID()
        self.fallbackDisplayName = profile?.displayName ?? "Carte User"
    }

    public func bootstrap() async {
        guard let store else { return }
        await runBusyOperation(successMessage: nil) {
            profile = try await store.loadProfile() ?? profile
            if let profile, profile.userNumber == nil, let identityDirectory {
                self.profile = try await identityDirectory.ensureIdentity(displayName: profile.displayName, existingProfile: profile)
                if let securedProfile = self.profile {
                    try await store.saveProfile(securedProfile)
                }
            }
            contacts = try await store.loadContacts()
            archive = try await store.loadArchive().sorted(by: { $0.deliveredAt > $1.deliveredAt })
            try await refreshInboxAndArchive()
        }
    }

    public func createProfile(displayName: String) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let draftProfile = UserProfile(displayName: trimmed.isEmpty ? "Carte User" : trimmed)
        let securedProfile = try await identityDirectory?.ensureIdentity(displayName: draftProfile.displayName, existingProfile: draftProfile) ?? draftProfile
        announceChange()
        profile = securedProfile
        try await store?.saveProfile(securedProfile)
        if let number = securedProfile.userNumber {
            statusMessage = "Profile ready. Your Carte number is #\(number)."
        } else {
            statusMessage = "Profile ready. Sign in to iCloud to receive a Carte number."
        }
    }

    public func addContact(displayName: String, inviteCode: String) async throws {
        guard let number = Int(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw CarteUserFacingError.invalidUserNumber
        }
        try await addContact(displayName: displayName, userNumber: number)
    }

    public func addContact(displayName: String, userNumber: Int) async throws {
        guard let contactBook else { return }
        let directoryContact = try await identityDirectory?.contact(forUserNumber: userNumber)
        let resolvedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? directoryContact?.displayName ?? "Carte #\(userNumber)"
            : displayName
        let contact = directoryContact.map { Contact(id: $0.id, displayName: resolvedName, userNumber: userNumber, note: $0.note) }
            ?? Contact(displayName: resolvedName, userNumber: userNumber)
        announceChange()
        contacts = try await contactBook.upsert(contact, into: contacts)
        statusMessage = "Added #\(userNumber)."
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
            senderNumber: profile.userNumber,
            front: content(text: draft.frontText, attachmentID: draft.frontAttachmentID, kind: draft.frontAttachmentKind),
            back: optionalBackContent()
        )
        _ = try await transport.send(card: card, to: [contact])
        announceChange()
        draft = ComposeDraft()
        statusMessage = "Sent to \(contact.displayName)."
    }

    public func sendDraft(toUserNumber userNumber: Int) async throws {
        let contact: Contact
        if let existing = contacts.first(where: { $0.userNumber == userNumber }) {
            contact = existing
        } else if let resolved = try await identityDirectory?.contact(forUserNumber: userNumber) {
            contact = resolved
            if let contactBook {
                contacts = try await contactBook.upsert(resolved, into: contacts)
            }
        } else {
            throw CarteUserFacingError.recipientNotFound(userNumber)
        }
        try await sendDraft(to: contact)
    }

    public func refreshInbox() async throws {
        let all = try await transport.inbox(for: currentUserAddress)
        announceChange()
        inbox = all.sorted(by: { $0.deliveredAt > $1.deliveredAt })
    }

    public func refreshInboxAndArchive() async throws {
        let remoteInbox = try await transport.inbox(for: currentUserAddress)
        let localArchive = try await store?.loadArchive() ?? archive
        announceChange()
        inbox = remoteInbox.filter(\.isInInbox).sorted(by: { $0.deliveredAt > $1.deliveredAt })
        archive = localArchive.sorted(by: { $0.deliveredAt > $1.deliveredAt })
    }

    public func erase(_ delivery: CardDelivery) async throws {
        if archive.contains(where: { $0.id == delivery.id }) {
            archive.removeAll { $0.id == delivery.id }
            try await store?.saveArchive(archive)
            announceChange()
            statusMessage = "Card erased."
            return
        }

        try await transport.erase(deliveryID: delivery.id, for: currentUserAddress)
        try await refreshInboxAndArchive()
        announceChange()
        statusMessage = "Card erased."
    }

    public func dismissToArchive(_ delivery: CardDelivery) async throws {
        var archivedDelivery = delivery
        archivedDelivery.archivedAt = .now

        var nextArchive = archive.filter { $0.id != archivedDelivery.id }
        nextArchive.insert(archivedDelivery, at: 0)
        try await store?.saveArchive(nextArchive)

        archive = nextArchive.sorted(by: { $0.deliveredAt > $1.deliveredAt })
        try await transport.erase(deliveryID: delivery.id, for: currentUserAddress)
        try await refreshInboxAndArchive()
        announceChange()
        statusMessage = "Saved to your archive."
    }

    @available(*, deprecated, message: "Use dismissToArchive(_:) so archived cards are stored locally and removed from transit.")
    public func archiveNow(_ delivery: CardDelivery) async throws {
        try await dismissToArchive(delivery)
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

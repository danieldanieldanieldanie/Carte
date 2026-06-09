import Foundation

public struct ContactBook: Sendable {
    private let store: any ProfileStore

    public init(store: any ProfileStore) {
        self.store = store
    }

    public func addContact(displayName: String, inviteCode: String, to contacts: [Contact]) async throws -> [Contact] {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = UUID(uuidString: trimmedCode) else {
            throw CarteUserFacingError.invalidInviteCode
        }

        var next = contacts.filter { $0.id != id }
        next.append(Contact(id: id, displayName: trimmedName.isEmpty ? "Carte Friend" : trimmedName))
        next.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        try await store.saveContacts(next)
        return next
    }

    public func removeContact(_ contact: Contact, from contacts: [Contact]) async throws -> [Contact] {
        let next = contacts.filter { $0.id != contact.id }
        try await store.saveContacts(next)
        return next
    }
}

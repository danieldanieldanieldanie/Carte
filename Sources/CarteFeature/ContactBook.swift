import Foundation

public struct ContactBook: Sendable {
    private let store: any ProfileStore

    public init(store: any ProfileStore) {
        self.store = store
    }

    public func addContact(displayName: String, inviteCode: String, to contacts: [Contact]) async throws -> [Contact] {
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCode = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if let number = Int(trimmedCode) {
            return try await upsert(Contact(displayName: trimmedName.isEmpty ? "Carte #\(number)" : trimmedName, userNumber: number), into: contacts)
        }

        guard let id = UUID(uuidString: trimmedCode) else {
            throw CarteUserFacingError.invalidInviteCode
        }

        return try await upsert(Contact(id: id, displayName: trimmedName.isEmpty ? "Carte Friend" : trimmedName), into: contacts)
    }

    public func upsert(_ contact: Contact, into contacts: [Contact]) async throws -> [Contact] {
        var next = contacts.filter { existing in
            existing.id != contact.id && existing.userNumber != contact.userNumber
        }
        next.append(contact)
        next.sort { lhs, rhs in
            switch (lhs.userNumber, rhs.userNumber) {
            case let (lhs?, rhs?) where lhs != rhs:
                return lhs < rhs
            default:
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        }
        try await store.saveContacts(next)
        return next
    }

    public func removeContact(_ contact: Contact, from contacts: [Contact]) async throws -> [Contact] {
        let next = contacts.filter { $0.id != contact.id }
        try await store.saveContacts(next)
        return next
    }
}

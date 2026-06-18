import Foundation

public protocol ProfileStore: Sendable {
    func loadProfile() async throws -> UserProfile?
    func saveProfile(_ profile: UserProfile) async throws
    func loadContacts() async throws -> [Contact]
    func saveContacts(_ contacts: [Contact]) async throws
    func loadArchive() async throws -> [CardDelivery]
    func saveArchive(_ archive: [CardDelivery]) async throws
}

public actor JSONProfileStore: ProfileStore {
    private let profileURL: URL
    private let contactsURL: URL
    private let archiveURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directory: URL? = nil) {
        let base = directory ?? URL.carteApplicationSupportDirectory()
        self.profileURL = base.appendingPathComponent("profile.json")
        self.contactsURL = base.appendingPathComponent("contacts.json")
        self.archiveURL = base.appendingPathComponent("archive.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    public func loadProfile() async throws -> UserProfile? {
        guard FileManager.default.fileExists(atPath: profileURL.path) else { return nil }
        let data = try Data(contentsOf: profileURL)
        return try decoder.decode(UserProfile.self, from: data)
    }

    public func saveProfile(_ profile: UserProfile) async throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(profile)
        try data.write(to: profileURL, options: [.atomic])
    }

    public func loadContacts() async throws -> [Contact] {
        guard FileManager.default.fileExists(atPath: contactsURL.path) else { return [] }
        let data = try Data(contentsOf: contactsURL)
        return try decoder.decode([Contact].self, from: data)
    }

    public func saveContacts(_ contacts: [Contact]) async throws {
        try ensureDirectoryExists()
        let data = try encoder.encode(contacts.sorted { $0.displayName < $1.displayName })
        try data.write(to: contactsURL, options: [.atomic])
    }

    public func loadArchive() async throws -> [CardDelivery] {
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return [] }
        let data = try Data(contentsOf: archiveURL)
        return try decoder.decode([CardDelivery].self, from: data)
    }

    public func saveArchive(_ archive: [CardDelivery]) async throws {
        try ensureDirectoryExists()
        let sorted = archive.sorted { $0.deliveredAt > $1.deliveredAt }
        let data = try encoder.encode(sorted)
        try data.write(to: archiveURL, options: [.atomic])
    }

    private func ensureDirectoryExists() throws {
        let directory = profileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}

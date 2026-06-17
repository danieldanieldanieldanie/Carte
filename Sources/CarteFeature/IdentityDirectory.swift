import Foundation

public protocol IdentityDirectory: Sendable {
    func ensureIdentity(displayName: String, existingProfile: UserProfile?) async throws -> UserProfile
    func contact(forUserNumber userNumber: Int) async throws -> Contact?
}

public actor InMemoryIdentityDirectory: IdentityDirectory {
    private var nextNumber: Int
    private var profilesByNumber: [Int: UserProfile]
    private var profileByID: [UUID: UserProfile]

    public init(startingAt nextNumber: Int = 0, profiles: [UserProfile] = []) {
        self.nextNumber = nextNumber
        self.profilesByNumber = Dictionary(uniqueKeysWithValues: profiles.compactMap { profile in
            guard let number = profile.userNumber else { return nil }
            return (number, profile)
        })
        self.profileByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        if let largest = profiles.compactMap(\.userNumber).max(), largest >= nextNumber {
            self.nextNumber = largest + 1
        }
    }

    public func ensureIdentity(displayName: String, existingProfile: UserProfile?) async throws -> UserProfile {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? existingProfile?.displayName ?? "Carte User" : trimmed

        if var existingProfile, let number = existingProfile.userNumber {
            existingProfile.displayName = resolvedName
            profilesByNumber[number] = existingProfile
            profileByID[existingProfile.id] = existingProfile
            return existingProfile
        }

        let number = nextNumber
        nextNumber += 1
        let profile = UserProfile(
            id: existingProfile?.id ?? UUID(),
            displayName: resolvedName,
            inviteCode: existingProfile?.inviteCode,
            userNumber: number,
            iCloudUserRecordName: existingProfile?.iCloudUserRecordName ?? "memory-\(number)",
            secureIdentityVersion: 1,
            createdAt: existingProfile?.createdAt ?? .now
        )
        profilesByNumber[number] = profile
        profileByID[profile.id] = profile
        return profile
    }

    public func contact(forUserNumber userNumber: Int) async throws -> Contact? {
        guard let profile = profilesByNumber[userNumber] else { return nil }
        return Contact(id: profile.id, displayName: profile.displayName, userNumber: userNumber)
    }
}

#if canImport(CloudKit)
import CloudKit

public actor CloudKitIdentityDirectory: IdentityDirectory {
    public static let identityRecordType = "CarteIdentity"
    public static let counterRecordType = "CarteNumberCounter"
    public static let counterRecordName = "global"

    private let container: CKContainer
    private let database: CKDatabase

    public init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.publicCloudDatabase
    }

    public func ensureIdentity(displayName: String, existingProfile: UserProfile?) async throws -> UserProfile {
        let status = try await container.accountStatus()
        guard status == .available else { throw CarteUserFacingError.missingSecureIdentity }

        let iCloudRecordID = try await container.userRecordID()
        let recordID = CKRecord.ID(recordName: iCloudRecordID.recordName)
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmed.isEmpty ? existingProfile?.displayName ?? "Carte User" : trimmed

        if let existing = try await fetchExistingIdentity(recordID: recordID) {
            existing["displayName"] = resolvedName as CKRecordValue
            existing["updatedAt"] = Date() as CKRecordValue
            let saved = try await database.save(existing)
            return try Self.decodeProfile(from: saved)
        }

        return try await allocateNumberAndCreateIdentity(
            recordID: recordID,
            iCloudRecordName: iCloudRecordID.recordName,
            displayName: resolvedName,
            existingProfile: existingProfile
        )
    }

    public func contact(forUserNumber userNumber: Int) async throws -> Contact? {
        let status = try await container.accountStatus()
        guard status == .available else { throw CarteUserFacingError.missingSecureIdentity }

        let predicate = NSPredicate(format: "userNumber == %lld", Int64(userNumber))
        let query = CKQuery(recordType: Self.identityRecordType, predicate: predicate)
        let result = try await database.records(matching: query, resultsLimit: 1)
        guard let first = result.matchResults.first else { return nil }
        let record = try first.1.get()
        let profile = try Self.decodeProfile(from: record)
        return Contact(id: profile.id, displayName: profile.displayName, userNumber: profile.userNumber)
    }

    private func fetchExistingIdentity(recordID: CKRecord.ID) async throws -> CKRecord? {
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func allocateNumberAndCreateIdentity(
        recordID: CKRecord.ID,
        iCloudRecordName: String,
        displayName: String,
        existingProfile: UserProfile?
    ) async throws -> UserProfile {
        while true {
            do {
                let counter = try await fetchOrCreateCounter()
                let next = (counter["nextNumber"] as? NSNumber)?.int64Value ?? 0
                counter["nextNumber"] = NSNumber(value: next + 1) as CKRecordValue

                let profile = UserProfile(
                    id: existingProfile?.id ?? UUID(),
                    displayName: displayName,
                    inviteCode: existingProfile?.inviteCode,
                    userNumber: Int(next),
                    iCloudUserRecordName: iCloudRecordName,
                    secureIdentityVersion: 1,
                    createdAt: existingProfile?.createdAt ?? .now
                )
                let identity = CKRecord(recordType: Self.identityRecordType, recordID: recordID)
                apply(profile: profile, iCloudRecordName: iCloudRecordName, to: identity)

                try await modifyRecordsAtomically(saving: [counter, identity])
                return profile
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue
            } catch let error as CKError where error.code == .constraintViolation {
                if let existing = try await fetchExistingIdentity(recordID: recordID) {
                    return try Self.decodeProfile(from: existing)
                }
                throw error
            }
        }
    }

    private func fetchOrCreateCounter() async throws -> CKRecord {
        let recordID = CKRecord.ID(recordName: Self.counterRecordName)
        do {
            return try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            let record = CKRecord(recordType: Self.counterRecordType, recordID: recordID)
            record["nextNumber"] = NSNumber(value: 0) as CKRecordValue
            do {
                return try await database.save(record)
            } catch let saveError as CKError where saveError.code == .serverRecordChanged || saveError.code == .constraintViolation {
                return try await database.record(for: recordID)
            }
        }
    }


    private func modifyRecordsAtomically(saving records: [CKRecord], deleting recordIDs: [CKRecord.ID] = []) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: recordIDs)
            operation.isAtomic = true
            operation.savePolicy = .ifServerRecordUnchanged
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result.map { _ in () })
            }
            database.add(operation)
        }
    }

    private func apply(profile: UserProfile, iCloudRecordName: String, to record: CKRecord) {
        record["appUserID"] = profile.id.uuidString as CKRecordValue
        record["displayName"] = profile.displayName as CKRecordValue
        record["inviteCode"] = profile.inviteCode as CKRecordValue
        record["userNumber"] = NSNumber(value: profile.userNumber ?? -1) as CKRecordValue
        record["iCloudUserRecordName"] = iCloudRecordName as CKRecordValue
        record["secureIdentityVersion"] = NSNumber(value: profile.secureIdentityVersion) as CKRecordValue
        record["createdAt"] = profile.createdAt as CKRecordValue
        record["updatedAt"] = Date() as CKRecordValue
    }

    private static func decodeProfile(from record: CKRecord) throws -> UserProfile {
        guard
            let appUserIDRaw = record["appUserID"] as? String,
            let appUserID = UUID(uuidString: appUserIDRaw),
            let displayName = record["displayName"] as? String,
            let inviteCode = record["inviteCode"] as? String,
            let numberRaw = record["userNumber"] as? NSNumber,
            let iCloudUserRecordName = record["iCloudUserRecordName"] as? String,
            let secureIdentityVersionRaw = record["secureIdentityVersion"] as? NSNumber,
            let createdAt = record["createdAt"] as? Date
        else {
            throw CloudKitTransportError.recordDecodeFailed
        }

        return UserProfile(
            id: appUserID,
            displayName: displayName,
            inviteCode: inviteCode,
            userNumber: numberRaw.intValue,
            iCloudUserRecordName: iCloudUserRecordName,
            secureIdentityVersion: secureIdentityVersionRaw.intValue,
            createdAt: createdAt
        )
    }
}
#else
public actor CloudKitIdentityDirectory: IdentityDirectory {
    public init() {}

    public func ensureIdentity(displayName: String, existingProfile: UserProfile?) async throws -> UserProfile {
        throw CloudKitTransportError.unsupportedPlatform
    }

    public func contact(forUserNumber userNumber: Int) async throws -> Contact? {
        throw CloudKitTransportError.unsupportedPlatform
    }
}
#endif

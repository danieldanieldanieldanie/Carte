import Foundation

public enum CarteAttachmentError: Error, LocalizedError, Sendable {
    case missingAttachment(String)

    public var errorDescription: String? {
        switch self {
        case .missingAttachment(let id):
            return "Carte could not find attachment \(id)."
        }
    }
}

public enum CarteAttachmentStore: Sendable {
    public static let photoExtension = "jpg"

    public static func attachmentsDirectory() throws -> URL {
        let directory = URL.carteApplicationSupportDirectory()
            .appendingPathComponent("Attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    public static func fileURL(for assetID: String, fileExtension: String = photoExtension) throws -> URL {
        try attachmentsDirectory().appendingPathComponent(assetID).appendingPathExtension(fileExtension)
    }

    @discardableResult
    public static func savePhotoData(_ data: Data, assetID: String = UUID().uuidString) throws -> String {
        let url = try fileURL(for: assetID)
        try data.write(to: url, options: [.atomic])
        return assetID
    }

    public static func existingPhotoURL(for assetID: String) -> URL? {
        guard let url = try? fileURL(for: assetID), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    @discardableResult
    public static func importPhotoFile(from sourceURL: URL, assetID: String = UUID().uuidString) throws -> String {
        let destination = try fileURL(for: assetID)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return assetID
    }
}

public extension URL {
    static func carteApplicationSupportDirectory() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Carte", isDirectory: true)
    }
}

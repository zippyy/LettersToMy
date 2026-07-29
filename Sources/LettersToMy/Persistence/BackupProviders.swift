import Foundation
import LettersToMyCore

// MARK: - Local File Backup Provider

/// Stores encrypted backup archives in a user-chosen directory on the
/// local filesystem. Useful for external drives, NAS mounts, and manual
/// export workflows.
final class LocalFileBackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .localFile
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func isReady() async -> Bool {
        let reachable = (try? directoryURL.checkResourceIsReachable()) ?? false
        let writable = FileManager.default.isWritableFile(atPath: directoryURL.path)
        return reachable && writable
    }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let archiveURL = directoryURL
            .appendingPathComponent(manifest.archiveID.uuidString)
            .appendingPathExtension("letterstomy")

        try archive.write(to: archiveURL, options: .atomic)

        return BackupRemoteHandle(
            identifier: manifest.archiveID.uuidString,
            location: archiveURL.path,
            metadata: [
                "path": archiveURL.path,
                "letters": "\(manifest.letterCount)",
                "recipients": "\(manifest.recipientCount)"
            ]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        let path = handle.metadata["path"] ?? handle.location
        guard !path.isEmpty else {
            throw BackupError.providerError(.localFile, "No file path in handle.")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "letterstomy" }
            .compactMap { url in
                let base = url.deletingPathExtension().lastPathComponent
                return BackupRemoteHandle(
                    identifier: base,
                    location: url.path,
                    metadata: ["path": url.path]
                )
            }
    }

    func remove(handle: BackupRemoteHandle) async throws {
        let path = handle.metadata["path"] ?? handle.location
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    func availableSpace() async throws -> Int64? {
        guard let values = try? directoryURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else {
            return nil
        }
        return Int64(capacity)
    }
}

// MARK: - iCloud Drive Backup Provider

/// Stores encrypted backup archives in the app's iCloud ubiquity
/// container so backups survive device loss and are available to
/// other devices signed into the same iCloud account.
final class ICloudBackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .iCloudDrive

    private var ubiquityURL: URL? {
        FileManager.default.url(
            forUbiquityContainerIdentifier: nil
        )?.appendingPathComponent("Backups", isDirectory: true)
    }

    private var fallbackURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("iCloudBackups", isDirectory: true)
    }

    func isReady() async -> Bool {
        let url = ubiquityURL ?? fallbackURL
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return true
    }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let url = ubiquityURL ?? fallbackURL

        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let archiveURL = url
            .appendingPathComponent(manifest.archiveID.uuidString)
            .appendingPathExtension("letterstomy")

        try archive.write(to: archiveURL, options: .atomic)

        return BackupRemoteHandle(
            identifier: manifest.archiveID.uuidString,
            location: archiveURL.path,
            metadata: ["path": archiveURL.path]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        let path = handle.metadata["path"] ?? handle.location
        guard !path.isEmpty else {
            throw BackupError.providerError(.iCloudDrive, "No file path in handle.")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        let url = ubiquityURL ?? fallbackURL
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        return contents
            .filter { $0.pathExtension == "letterstomy" }
            .compactMap { url in
                let base = url.deletingPathExtension().lastPathComponent
                return BackupRemoteHandle(
                    identifier: base,
                    location: url.path,
                    metadata: ["path": url.path]
                )
            }
    }

    func remove(handle: BackupRemoteHandle) async throws {
        let path = handle.metadata["path"] ?? handle.location
        guard !path.isEmpty else { return }
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
    }

    func availableSpace() async throws -> Int64? {
        let url = ubiquityURL ?? fallbackURL
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else { return nil }
        return Int64(capacity)
    }
}

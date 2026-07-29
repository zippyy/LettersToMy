import Foundation
import LettersToMyCore

/// Stores backup archives on a Synology NAS via a mounted network share
/// or direct SMB/AFP path. The user provides a directory URL (either a
/// mounted volume path or a file:// URL to a network share).
final class SynologyBackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .synologyNAS
    private let directoryURL: URL
    private let fileManager = FileManager.default

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    func isReady() async -> Bool {
        let reachable = (try? directoryURL.checkResourceIsReachable()) ?? false
        let writable = fileManager.isWritableFile(atPath: directoryURL.path)
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
            metadata: ["path": archiveURL.path]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        let path = handle.metadata["path"] ?? handle.location
        guard !path.isEmpty else {
            throw BackupError.providerError(.synologyNAS, "No file path in handle.")
        }
        return try Data(contentsOf: URL(fileURLWithPath: path))
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else { return [] }

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
        try? fileManager.removeItem(at: URL(fileURLWithPath: path))
    }

    func availableSpace() async throws -> Int64? {
        guard let values = try? directoryURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity else { return nil }
        return Int64(capacity)
    }
}
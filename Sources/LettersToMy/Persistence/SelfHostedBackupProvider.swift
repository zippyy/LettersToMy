import Foundation
import LettersToMyCore

/// Backup destination backed by the self-hosted server.
///
/// The archive travels as an opaque encrypted blob: the client encrypts
/// with the user's passphrase (AES-256-GCM via BackupService) and the
/// server stores it without ever seeing the passphrase or plaintext.
///
/// The provider captures a configuration snapshot at registration time.
/// When the snapshot is not configured, every operation fails honestly
/// with `BackupError.notConfigured(.selfHosted)` — never a fake success.
final class SelfHostedBackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .selfHosted
    private let config: SelfHostedConfigSnapshot

    init(config: SelfHostedConfigSnapshot) {
        self.config = config
    }

    private func client() throws -> SelfHostedAPIClient {
        guard config.isConfigured else {
            throw BackupError.notConfigured(.selfHosted)
        }
        do {
            return try SelfHostedAPIClient(serverURL: config.serverURL, apiToken: config.apiToken)
        } catch {
            throw BackupError.notConfigured(.selfHosted)
        }
    }

    func isReady() async -> Bool {
        guard config.isConfigured else { return false }
        do {
            let client = try client()
            _ = try await client.serverIdentity()
            return true
        } catch {
            return false
        }
    }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let client = try client()
        let id = manifest.archiveID.uuidString
        let meta = try await client.uploadBackup(id: id, data: archive, letterCount: manifest.letterCount)
        return BackupRemoteHandle(
            identifier: meta.id,
            location: "",
            metadata: [
                "size": "\(meta.size)",
                "timestamp": "\(meta.timestamp)",
                "letters": "\(meta.letterCount)"
            ]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        let client = try client()
        return try await client.downloadBackup(id: handle.identifier)
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        let client = try client()
        let backups = try await client.listBackups()
        return backups.map { meta in
            BackupRemoteHandle(
                identifier: meta.id,
                location: "",
                metadata: [
                    "size": "\(meta.size)",
                    "timestamp": "\(meta.timestamp)",
                    "letters": "\(meta.letterCount)"
                ]
            )
        }
    }

    func remove(handle: BackupRemoteHandle) async throws {
        let client = try client()
        try await client.deleteBackup(id: handle.identifier)
    }

    /// The self-hosted server does not advertise free space.
    func availableSpace() async throws -> Int64? {
        nil
    }
}
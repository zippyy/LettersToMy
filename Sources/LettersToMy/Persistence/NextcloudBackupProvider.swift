import Foundation
import LettersToMyCore

/// Nextcloud uses WebDAV under the hood. This provider wraps the
/// WebDAV implementation with the Nextcloud destination identifier.
final class NextcloudBackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .nextcloud
    private let webdav: WebDAVBackupProvider

    init(baseURL: URL, username: String? = nil, password: String? = nil) {
        // Nextcloud's WebDAV endpoint is at /remote.php/dav/files/<username>/
        webdav = WebDAVBackupProvider(baseURL: baseURL, username: username, password: password)
    }

    func isReady() async -> Bool { await webdav.isReady() }
    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        try await webdav.store(archive: archive, manifest: manifest)
    }
    func retrieve(handle: BackupRemoteHandle) async throws -> Data { try await webdav.retrieve(handle: handle) }
    func listRemoteBackups() async throws -> [BackupRemoteHandle] { try await webdav.listRemoteBackups() }
    func remove(handle: BackupRemoteHandle) async throws { try await webdav.remove(handle: handle) }
    func availableSpace() async throws -> Int64? { try await webdav.availableSpace() }
}
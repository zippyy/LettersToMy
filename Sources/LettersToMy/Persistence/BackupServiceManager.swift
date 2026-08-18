import Foundation
import LettersToMyCore

/// Application-level singleton that owns the BackupService and
/// registers the providers available on the current platform.
@MainActor
final class BackupServiceManager {
    static let shared = BackupServiceManager()

    let service = BackupService(
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    )

    @Published private(set) var isReady = false

    private init() {
        Task { await registerProviders() }
    }

    private func registerProviders() async {
        // Local file
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            let dir = docs.appendingPathComponent("Backups", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            await service.register(LocalFileBackupProvider(directoryURL: dir))
        }

        // iCloud Drive
        await service.register(ICloudBackupProvider())

        // Other providers registered with placeholder configs.
        // Google Drive
        await service.register(GoogleDriveBackupProvider())

        // Synology
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            await service.register(SynologyBackupProvider(directoryURL: docs))
        }

        // Nextcloud
        if let url = URL(string: "https://nextcloud.example.com/remote.php/dav/files/") {
            await service.register(NextcloudBackupProvider(baseURL: url))
        }

        // WebDAV
        if let url = URL(string: "https://webdav.example.com/") {
            await service.register(WebDAVBackupProvider(baseURL: url))
        }

        // S3
        if let url = URL(string: "https://s3.amazonaws.com") {
            await service.register(S3BackupProvider(
                endpointURL: url,
                bucket: "letters-to-my-backups",
                accessKey: "",
                secretKey: ""
            ))
        }

        isReady = true
    }
}
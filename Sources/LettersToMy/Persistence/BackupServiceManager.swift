import Foundation
import LettersToMyCore

/// Application-level singleton that owns the BackupService and
/// registers the providers available on the current platform.
@MainActor
final class BackupServiceManager {
    static let shared = BackupServiceManager()

    let service = BackupService(appVersion: "0.1.0")

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

        // Google Drive — requires OAuth credentials to actually work;
        // registered here so the destination appears as available.
        await service.register(GoogleDriveBackupProvider())

        // Synology NAS — requires a mounted/directory URL to work;
        // registered with the app's Documents directory as a placeholder.
        // The user should configure this via settings.
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            await service.register(SynologyBackupProvider(directoryURL: docs))
        }

        // Nextcloud — requires base URL and credentials.
        // Registered with a placeholder URL; user configures via settings.
        if let placeholder = URL(string: "https://nextcloud.example.com/remote.php/dav/files/") {
            await service.register(NextcloudBackupProvider(baseURL: placeholder))
        }

        // WebDAV — requires base URL and optional credentials.
        if let placeholder = URL(string: "https://webdav.example.com/") {
            await service.register(WebDAVBackupProvider(baseURL: placeholder))
        }

        // S3 Compatible — requires endpoint, bucket, and credentials.
        if let placeholder = URL(string: "https://s3.amazonaws.com") {
            await service.register(S3BackupProvider(
                endpointURL: placeholder,
                bucket: "letters-to-my-backups",
                accessKey: "",
                secretKey: ""
            ))
        }
    }
}
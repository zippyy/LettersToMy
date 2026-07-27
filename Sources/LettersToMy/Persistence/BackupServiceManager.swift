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
        // Local file — writes to the app's Documents/Backups directory.
        if let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first {
            let dir = docs.appendingPathComponent("Backups", isDirectory: true)
            try? FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            await service.register(LocalFileBackupProvider(directoryURL: dir))
        }

        // iCloud Drive — uses the app's ubiquitous container.
        await service.register(ICloudBackupProvider())
    }
}

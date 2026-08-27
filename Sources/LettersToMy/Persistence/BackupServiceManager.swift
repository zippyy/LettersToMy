import Foundation
import LettersToMyCore

/// Application-level singleton that owns the BackupService and
/// registers the providers available on the current platform.
@MainActor
final class BackupServiceManager: ObservableObject {
    static let shared = BackupServiceManager()

    let service = BackupService(
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    )

    @Published private(set) var isReady = false

    /// Destinations that have a REAL provider registered. The backup UI
    /// lists only these; destinations without credentials are not shown
    /// as if they were usable.
    @Published private(set) var availableDestinations: [BackupDestination] = []

    private init() {
        Task { await registerProviders() }
    }

    private func registerProviders() async {
        // Only providers with REAL configuration are registered. Placeholder
        // registrations (example.com URLs, empty keys, a "Synology" provider
        // pointed at the local Documents directory) would make the UI claim a
        // backup succeeded when nothing was actually stored at the destination
        // — a silent data-loss hazard. Unregistered destinations fail honestly
        // with BackupError.notConfigured ("<Destination> is not configured.").
        //
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

        availableDestinations = [.localFile, .iCloudDrive]
        isReady = true
    }
}
import Foundation
import LettersToMyCore

// MARK: - Snapshot (plain, Sendable)

/// A point-in-time copy of the self-hosted configuration. Providers
/// capture a snapshot when they are registered so they never need to
/// cross actors to read UI state.
struct SelfHostedConfigSnapshot: Sendable {
    var serverURL: String
    var apiToken: String
    var isConfigured: Bool {
        !serverURL.isEmpty && !apiToken.isEmpty
    }
}

// MARK: - Observable configuration

/// App-level configuration for the self-hosted server (Settings →
/// Self-Hosted Server).
///
/// Storage:
///   * server URL — UserDefaults (non-sensitive preference)
///   * API token — Keychain (credential, never plain UserDefaults)
///   * enabled — UserDefaults
@MainActor
final class SelfHostedConfig: ObservableObject {
    static let shared = SelfHostedConfig()

    // Immutable constants; nonisolated so the nonisolated loadSnapshot()
    // (used by BackupServiceManager off the main actor) can reference them.
    nonisolated static let serverURLKey = "selfHostedServerURL"
    nonisolated static let enabledKey = "selfHostedEnabled"
    nonisolated static let tokenAccount = "selfHostedAPIToken"

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: SelfHostedConfig.serverURLKey) }
    }
    @Published var apiToken: String {
        didSet { KeychainHelper.set(apiToken, for: SelfHostedConfig.tokenAccount) }
    }
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: SelfHostedConfig.enabledKey) }
    }

    private init() {
        serverURL = UserDefaults.standard.string(forKey: SelfHostedConfig.serverURLKey) ?? ""
        apiToken = KeychainHelper.get(SelfHostedConfig.tokenAccount) ?? ""
        enabled = UserDefaults.standard.bool(forKey: SelfHostedConfig.enabledKey)
    }

    var isConfigured: Bool {
        !serverURL.isEmpty && !apiToken.isEmpty
    }

    var snapshot: SelfHostedConfigSnapshot {
        SelfHostedConfigSnapshot(serverURL: serverURL, apiToken: apiToken)
    }

    /// Build a live API client from the current configuration.
    func makeClient() throws -> SelfHostedAPIClient {
        try SelfHostedAPIClient(serverURL: serverURL, apiToken: apiToken)
    }

    /// Remove the server URL, token, and enabled state.
    func clear() {
        serverURL = ""
        apiToken = ""
        enabled = false
        KeychainHelper.delete(SelfHostedConfig.tokenAccount)
        UserDefaults.standard.removeObject(forKey: SelfHostedConfig.serverURLKey)
        UserDefaults.standard.removeObject(forKey: SelfHostedConfig.enabledKey)
    }

    /// Read the persisted configuration from raw storage. Nonisolated so
    /// BackupServiceManager can build a provider snapshot without hopping
    /// to the main actor.
    nonisolated static func loadSnapshot() -> SelfHostedConfigSnapshot {
        let url = UserDefaults.standard.string(forKey: SelfHostedConfig.serverURLKey) ?? ""
        let token = KeychainHelper.get(SelfHostedConfig.tokenAccount) ?? ""
        return SelfHostedConfigSnapshot(serverURL: url, apiToken: token)
    }
}
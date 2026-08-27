import LettersToMyCore
import SwiftUI

/// Settings → Self-Hosted Server.
///
/// Configure the LettersToMy-SelfHostedSync server: server URL (plain
/// UserDefaults), API token (Keychain), enable/disable, and a genuine
/// connection test that contacts the server and validates its identity
/// and API version — never a bare-200 success.
struct SelfHostedSettingsView: View {
    @StateObject private var config = SelfHostedConfig.shared

    @State private var connectionState: SelfHostedConnectionState = .notConfigured
    @State private var isTesting = false
    @State private var capabilityText = ""

    var body: some View {
        Form {
            Section {
                connectionRow
            } header: {
                Text("Status")
            }

            Section("Server") {
                TextField("https://letters.example.com", text: $config.serverURL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .disabled(config.enabled)
                Text("For local testing you can use http://192.168.x.x:8080.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("API Token") {
                SecureField("Token", text: $config.apiToken)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .disabled(config.enabled)
                Text("Stored in the Keychain. The server sends it as a Bearer token on every request.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Enable Self-Hosted Integration", isOn: $config.enabled)
            } footer: {
                Text("When enabled, this server can store encrypted backups. CloudKit remains the source of truth for your archive; the server never sees plaintext letters.")
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.small)
                        Text("Checking…")
                    } else {
                        Label("Test Connection", systemImage: "bolt.horizontal")
                    }
                }
                .disabled(isTesting || !config.enabled || !config.isConfigured)

                Button("Clear Configuration", role: .destructive) {
                    config.clear()
                    connectionState = .notConfigured
                    capabilityText = ""
                }
                .disabled(!config.isConfigured)
            }

            if !capabilityText.isEmpty {
                Section("Capabilities") {
                    Text(capabilityText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Self-Hosted Server")
        .onAppear { loadCurrentState() }
        .onChange(of: config.enabled) { _, enabled in
            if !enabled {
                connectionState = .notConfigured
                capabilityText = ""
            } else if config.isConfigured {
                Task { await testConnection() }
            }
        }
    }

    private var connectionRow: some View {
        HStack {
            Image(systemName: connectionState.systemImage)
                .foregroundStyle(colorForState(connectionState))
            Text(connectionState.label)
                .foregroundStyle(connectionState.isConnected ? .primary : .secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func colorForState(_ state: SelfHostedConnectionState) -> Color {
        switch state {
        case .connected: .green
        case .notConfigured, .checking: .secondary
        case .authenticationFailed, .unreachable, .incompatible, .serverError: .red
        }
    }

    private func loadCurrentState() {
        if !config.isConfigured {
            connectionState = .notConfigured
        } else if connectionState == .notConfigured {
            // Do not auto-test on appear (avoid a network call the user
            // did not ask for); just report "Not checked" until they tap
            // Test Connection.
        }
    }

    private func testConnection() async {
        guard config.enabled, config.isConfigured else {
            connectionState = .notConfigured
            return
        }
        isTesting = true
        defer { isTesting = false }
        connectionState = .checking

        let client: SelfHostedAPIClient
        do {
            client = try config.makeClient()
        } catch let error as SelfHostedAPIError {
            connectionState = .incompatible(error.localizedDescription)
            capabilityText = ""
            return
        } catch {
            connectionState = .serverError(error.localizedDescription)
            capabilityText = ""
            return
        }

        // Run the full capability probe against the live server.
        let check = SelfHostedCapabilityCheck(client: client)
        let report = await check.run()

        if let identity = report.identity {
            connectionState = .connected(identity)
            var lines = ["\(identity.displayName)", "API v\(identity.apiVersion)"]
            lines.append("Capabilities: \(identity.capabilities.joined(separator: ", "))")
            capabilityText = lines.joined(separator: "\n")
        } else {
            connectionState = .unreachable("could not contact server")
            capabilityText = ""
            return
        }

        // Surface per-feature probe failures too.
        var failures: [String] = []
        if case .failure(let e) = report.collaboration { failures.append("collaboration: \(e.localizedDescription)") }
        if case .failure(let e) = report.backups { failures.append("backups: \(e.localizedDescription)") }
        if case .failure(let e) = report.attachments { failures.append("attachments: \(e.localizedDescription)") }
        if !failures.isEmpty {
            connectionState = .serverError(failures.joined(separator: "\n"))
        }
    }
}
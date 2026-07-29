import SwiftUI

struct SettingsView: View {
    @AppStorage("recipientPreview") private var recipientPreview = false
    @ObservedObject private var persistence = PersistenceController.shared

    private var iCloudStatus: String {
        if !PersistenceController.cloudKitAvailable { return "Unavailable" }
        return switch persistence.cloudKitAccountStatus {
        case .available: "Available"
        case .noAccount: "Not signed in"
        case .restricted: "Restricted"
        case .couldNotDetermine: "Checking…"
        case .temporarilyUnavailable: "Temporarily unavailable"
        @unknown default: "Unknown"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    Toggle("Recipient preview", isOn: $recipientPreview)
                    Text("When enabled, sealed letters remain hidden until their unlock rules are satisfied. Parents can turn this off to manage the complete archive.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("iCloud") {
                    LabeledContent("Account", value: iCloudStatus)
                    if let error = persistence.lastSyncError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Text("Owned content synchronizes through the private CloudKit store. Invitations accepted from another family archive synchronize through the shared CloudKit store.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Collaboration") {
                    Label("Private and shared Core Data stores", systemImage: "externaldrive.connected.to.line.below")
                    Label("Scoped CloudKit sharing for family sides, folders, and recipients", systemImage: "person.2")
                    Label("System share-link acceptance on iPhone, iPad, and Mac", systemImage: "icloud")
                }

                Section("Backups") {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        Label("Manage Backups", systemImage: "arrow.up.doc")
                    }
                    Text("Encrypted archives can be stored locally, in iCloud Drive, or on external storage. Use a strong passphrase and keep it somewhere safe.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Recovery") {
                    NavigationLink {
                        RecoveryContactsView()
                    } label: {
                        Label("Recovery Contacts", systemImage: "person.badge.key")
                    }
                    Text("Designate people who can help recover your archive through a defined process. They do not gain access until you initiate recovery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Release requirements") {
                    Label("Encrypted archive export and recovery contacts", systemImage: "lock.doc")
                    Label("Participant revocation and multi-account integration tests", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Integrated web client using the same CloudKit container", systemImage: "safari")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

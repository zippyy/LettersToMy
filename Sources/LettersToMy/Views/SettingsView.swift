import CloudKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("recipientPreview") private var recipientPreview = false
    @State private var iCloudStatus = "Checking…"

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

                Section("Release requirements") {
                    Label("Encrypted archive export and recovery contacts", systemImage: "lock.doc")
                    Label("Participant revocation and multi-account integration tests", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Integrated web client using the same CloudKit container", systemImage: "safari")
                }
            }
            .navigationTitle("Settings")
        }
        .task { await refreshCloudStatus() }
    }

    private func refreshCloudStatus() async {
        do {
            switch try await CKContainer.default().accountStatus() {
            case .available:
                iCloudStatus = "Available"
            case .noAccount:
                iCloudStatus = "Not signed in"
            case .restricted:
                iCloudStatus = "Restricted"
            case .couldNotDetermine:
                iCloudStatus = "Unavailable"
            case .temporarilyUnavailable:
                iCloudStatus = "Temporarily unavailable"
            @unknown default:
                iCloudStatus = "Unknown"
            }
        } catch {
            iCloudStatus = "Unavailable"
        }
    }
}

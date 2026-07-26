import CloudKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("recipientPreview") private var recipientPreview = false
    @State private var iCloudStatus = "Checking…"

    var body: some View {
        Form {
            Section("Preview") {
                Toggle("Recipient preview", isOn: $recipientPreview)
                Text("When enabled, sealed letters remain hidden until their unlock rules are satisfied. Parents can turn this off to manage the complete archive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("iCloud") {
                LabeledContent("Account", value: iCloudStatus)
                Text("Letters and attachments synchronize through the app’s private CloudKit database across signed-in Apple devices.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Roadmap") {
                Label("Encrypted archive export and recovery contacts", systemImage: "lock.doc")
                Label("Family collaboration through CloudKit sharing", systemImage: "person.2")
                Label("Integrated web client using the same CloudKit container", systemImage: "safari")
            }
        }
        .navigationTitle("Settings")
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

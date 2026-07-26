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
                Text("The current prototype synchronizes owned records through the private CloudKit database. Shared collaborator records will use private and shared CloudKit stores after the Core Data migration.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Collaboration") {
                Label("Roles, family sides, folders, and invitation plans are available", systemImage: "person.3.fill")
                Label("Live private iCloud invitations require the shared-store migration", systemImage: "icloud.and.arrow.up")
                Label("Recipients receive only their own unlocked deliveries", systemImage: "tray.full.fill")
            }

            Section("Release requirements") {
                Label("Encrypted archive export and recovery contacts", systemImage: "lock.doc")
                Label("CloudKit invitation acceptance and revocation", systemImage: "person.crop.circle.badge.checkmark")
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

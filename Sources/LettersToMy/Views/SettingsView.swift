import LettersToMyCore
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

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    private var canManagePreview: Bool {
        PersistenceController.shared.canPerform(
            .viewSealedContent,
            context: CollaborationContext(isSealed: true)
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Preview") {
                    Toggle("Recipient preview", isOn: $recipientPreview)
                        .disabled(!canManagePreview)
                    Text(canManagePreview
                        ? "When enabled, sealed letters remain hidden until their unlock rules are satisfied. Parents can turn this off to manage the complete archive."
                        : "Only owners and administrators can disable recipient preview. Sealed letters stay hidden from collaborators.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                #if os(iOS)
                Section("App Icon") {
                    Picker("Icon", selection: $selectedIcon) {
                        ForEach(AppIcon.allCases, id: \.self) { icon in
                            HStack {
                                icon.preview
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                Text(icon.label)
                            }
                            .tag(icon)
                        }
                    }
                    .onChange(of: selectedIcon) { _, icon in
                        UIApplication.shared.setAlternateIconName(icon.name)
                        AppAnalytics.iconChanged(icon.name ?? "default")
                    }
                }
                #endif

                Section("iCloud") {
                    LabeledContent("Account", value: iCloudStatus)
                    if let error = persistence.lastSyncError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Text("Owned content synchronizes through the private CloudKit store.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Collaboration") {
                    Label("Private and shared Core Data stores", systemImage: "externaldrive.connected.to.line.below")
                    Label("Scoped CloudKit sharing for family sides, folders, and recipients", systemImage: "person.2")
                    Label("System share-link acceptance on iPhone, iPad, and Mac", systemImage: "icloud")
                }

                Section("Backups") {
                    NavigationLink { BackupSettingsView() } label: {
                        Label("Manage Backups", systemImage: "arrow.up.doc")
                    }
                }

                Section("Self-Hosted") {
                    NavigationLink { SelfHostedSettingsView() } label: {
                        Label("Self-Hosted Server", systemImage: "server.rack")
                    }
                }

                Section("Recovery") {
                    NavigationLink { RecoveryContactsView() } label: {
                        Label("Recovery Contacts", systemImage: "person.badge.key")
                    }
                }

                Section("Release requirements") {
                    Label("Encrypted archive export and recovery contacts", systemImage: "lock.doc")
                    Label("Participant revocation and multi-account integration tests", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Integrated web client using the same CloudKit container", systemImage: "safari")
                }

                Section {
                    LabeledContent("Version", value: "\(appVersion) (\(buildNumber))")
                } footer: {
                    Text("LettersToMy \(appVersion) (\(buildNumber)) — CloudKit \(PersistenceController.cloudKitContainerIdentifier)")
                }
            }
            .navigationTitle("Settings")
        }
    }

    #if os(iOS)
    @AppStorage("selectedAppIcon") private var selectedIconName: String = ""
    @State private var selectedIcon = AppIcon.default

    private enum AppIcon: String, CaseIterable {
        case `default`
        case Daughter = "AppIcon-Daughter"
        case Granddaughter = "AppIcon-Granddaughter"
        case Grandson = "AppIcon-Grandson"
        case Son = "AppIcon-Son"

        var label: String {
            switch self {
            case .default: return "Default"
            case .Daughter: return "Daughter"
            case .Granddaughter: return "Granddaughter"
            case .Grandson: return "Grandson"
            case .Son: return "Son"
            }
        }

        var name: String? { self == .default ? nil : rawValue }

        var previewImageName: String {
            guard self != .default else { return "icon-preview-default" }
            return "icon-preview-\(label)"
        }

        var preview: Image {
            if let img = UIImage(named: previewImageName) {
                return Image(uiImage: img)
            }
            return Image(systemName: "app.fill")
        }
    }
    #endif
}

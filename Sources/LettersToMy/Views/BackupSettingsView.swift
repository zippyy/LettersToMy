import CoreData
import LettersToMyCore
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BackupRecordEntity.createdAt, ascending: false)],
        animation: .default
    ) private var backupRecords: FetchedResults<BackupRecordEntity>

    @State private var passphrase = ""
    @State private var isBackingUp = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var showingPassphrasePrompt = false
    @State private var pendingDestination: BackupDestination?

    // Restore state
    @State private var showingRestoreImporter = false
    @State private var restorePassphrase = ""
    @State private var restorePayload: BackupPayload?
    @State private var showingRestorePreview = false
    @State private var restoreProgress = ""

    private var service: BackupService { BackupServiceManager.shared.service }

    var body: some View {
        Form {
            destinationsSection
            passphraseSection
            actionsSection
            restoreSection
            historySection
        }
        .navigationTitle("Backups")
        .alert(statusIsError ? "Backup Failed" : "Backup Complete",
               isPresented: Binding(
                get: { statusMessage != nil },
                set: { if !$0 { statusMessage = nil } }
               )) {
            Button("OK") { statusMessage = nil }
        } message: {
            Text(statusMessage ?? "")
        }
        .fileImporter(
            isPresented: $showingRestoreImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleRestoreImport(result)
        }
        .sheet(isPresented: $showingRestorePreview) {
            restorePreviewSheet
        }
    }

    // MARK: - Destinations

    private var destinationsSection: some View {
        Section("Destinations") {
            ForEach(BackupDestination.allCases, id: \.self) { destination in
                destinationRow(for: destination)
            }
        }
    }

    private func destinationRow(for destination: BackupDestination) -> some View {
        HStack {
            Image(systemName: destination.systemImage)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.title)
                    .font(.body)
                if let lastRecord = latestRecord(for: destination) {
                    Text("Last backup \(lastRecord.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isBackingUp {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    pendingDestination = destination
                    Task { await backupNow(to: destination) }
                } label: {
                    Label("Back Up Now", systemImage: "arrow.up.doc")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(passphrase.isEmpty || isBackingUp)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Passphrase

    private var passphraseSection: some View {
        Section("Encryption Passphrase") {
            SecureField("Passphrase", text: $passphrase)
            Text("This passphrase encrypts every backup. Store it somewhere safe — if you lose it you cannot restore the archive.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section("Manual Controls") {
            Button {
                Task { await backupNow(to: .localFile) }
            } label: {
                Label("Save Backup to Local File", systemImage: "folder")
            }
            .disabled(passphrase.isEmpty || isBackingUp)

            Button {
                Task { await backupNow(to: .iCloudDrive) }
            } label: {
                Label("Save Backup to iCloud Drive", systemImage: "icloud")
            }
            .disabled(passphrase.isEmpty || isBackingUp)
        }
    }

    // MARK: - Restore

    private var restoreSection: some View {
        Section("Restore from Backup") {
            Button {
                showingRestoreImporter = true
            } label: {
                Label("Import .letterstomy File", systemImage: "arrow.down.doc")
            }

            if !restoreProgress.isEmpty {
                Text(restoreProgress)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        Section("Backup History") {
            if backupRecords.isEmpty {
                Text("No backups yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backupRecords) { record in
                    HistoryRow(record: record, onDelete: {
                        deleteRecord(record)
                    })
                }
            }
        }
    }

    // MARK: - Operations

    private func backupNow(to destination: BackupDestination) async {
        isBackingUp = true
        statusMessage = nil
        defer { isBackingUp = false }

        guard !passphrase.isEmpty else {
            statusMessage = "Please enter a backup passphrase."
            statusIsError = true
            return
        }

        let payload = buildPayload()
        let record: BackupRecord
        do {
            record = try await service.backup(
                payload: payload,
                to: destination,
                passphrase: passphrase
            )
        } catch {
            statusMessage = error.localizedDescription
            statusIsError = true
            return
        }

        // Persist the record.
        let entity = PersistenceController.shared.insertPrivate(
            BackupRecordEntity.self,
            into: context
        )
        entity.apply(record)
        try? PersistenceController.shared.save(context)

        statusMessage = "\(destination.title) backup complete — \(record.letterCount) letters, \(formatBytes(record.sizeBytes))."
        statusIsError = false
    }

    private func deleteRecord(_ entity: BackupRecordEntity) {
        context.delete(entity)
        try? PersistenceController.shared.save(context)
    }

    private func buildPayload() -> BackupPayload {
        let childrenFetch = NSFetchRequest<ChildProfile>(entityName: "ChildProfile")
        let lettersFetch = NSFetchRequest<Letter>(entityName: "Letter")
        let attachmentsFetch = NSFetchRequest<LetterAttachment>(entityName: "LetterAttachment")
        let branchesFetch = NSFetchRequest<FamilyBranchRecord>(entityName: "FamilyBranchRecord")
        let foldersFetch = NSFetchRequest<ArchiveFolderRecord>(entityName: "ArchiveFolderRecord")
        let membersFetch = NSFetchRequest<ArchiveMemberRecord>(entityName: "ArchiveMemberRecord")
        let invitationsFetch = NSFetchRequest<CollaborationInvitationRecord>(entityName: "CollaborationInvitationRecord")

        let children = (try? context.fetch(childrenFetch)) ?? []
        let letters = (try? context.fetch(lettersFetch)) ?? []
        let attachments = (try? context.fetch(attachmentsFetch)) ?? []
        let branches = (try? context.fetch(branchesFetch)) ?? []
        let folders = (try? context.fetch(foldersFetch)) ?? []
        let members = (try? context.fetch(membersFetch)) ?? []
        let invitations = (try? context.fetch(invitationsFetch)) ?? []

        return BackupPayload(
            children: children.map {
                ChildPayload(id: $0.id, name: $0.name, birthDate: $0.birthDate)
            },
            letters: letters.map {
                LetterPayload(
                    id: $0.id,
                    childID: $0.childID,
                    branchID: $0.branchID,
                    folderID: $0.folderID,
                    authorMemberID: $0.authorMemberID,
                    title: $0.title,
                    body: $0.body,
                    authorName: $0.authorName,
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt,
                    sealedAt: $0.sealedAt,
                    isFavorite: $0.isFavorite,
                    unlockRuleRawValue: $0.unlockRuleRawValue,
                    unlockDate: $0.unlockDate,
                    unlockAgeYearsValue: $0.unlockAgeYears,
                    lifeEventName: $0.lifeEventName,
                    manuallyReleasedAt: $0.manuallyReleasedAt
                )
            },
            attachments: attachments.compactMap {
                guard let data = $0.data else { return nil }
                return AttachmentPayload(
                    id: $0.id,
                    letterID: $0.letterID,
                    fileName: $0.fileName,
                    contentTypeIdentifier: $0.contentTypeIdentifier,
                    kindRawValue: $0.kindRawValue,
                    createdAt: $0.createdAt,
                    data: data
                )
            },
            branches: branches.map {
                BranchPayload(
                    id: $0.id,
                    name: $0.name,
                    kindRawValue: $0.kindRawValue,
                    parentBranchID: $0.parentBranchID
                )
            },
            folders: folders.map {
                FolderPayload(
                    id: $0.id,
                    branchID: $0.branchID,
                    parentFolderID: $0.parentFolderID,
                    name: $0.name
                )
            },
            members: members.map {
                MemberPayload(
                    id: $0.id,
                    displayName: $0.displayName,
                    relationship: $0.relationship,
                    roleRawValue: $0.roleRawValue,
                    statusRawValue: $0.statusRawValue,
                    canInviteOthers: $0.canInviteOthers
                )
            },
            invitations: invitations.map {
                InvitationPayload(
                    id: $0.id,
                    inviteeDisplayName: $0.inviteeDisplayName,
                    inviteeAddress: $0.inviteeAddress,
                    relationship: $0.relationship,
                    roleRawValue: $0.roleRawValue,
                    statusRawValue: $0.statusRawValue
                )
            }
        )
    }

    private func latestRecord(for destination: BackupDestination) -> BackupRecordEntity? {
        backupRecords.first { $0.destination == destination }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    // MARK: - Restore

    private func handleRestoreImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }

            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }

            let data = try Data(contentsOf: url)
            let payload = try BackupService.decryptPayload(
                data: data,
                passphrase: restorePassphrase.isEmpty ? passphrase : restorePassphrase
            )
            restorePayload = payload
            showingRestorePreview = true
            restoreProgress = ""
        } catch {
            restoreProgress = "Decryption failed: \(error.localizedDescription)"
            restorePayload = nil
        }
    }

    @ViewBuilder
    private var restorePreviewSheet: some View {
        NavigationStack {
            if let payload = restorePayload {
                Form {
                    Section("Archive Preview") {
                        LabeledContent("Letters", value: "\(payload.letters.count)")
                        LabeledContent("Attachments", value: "\(payload.attachments.count)")
                        LabeledContent("Recipients", value: "\(payload.children.count)")
                        LabeledContent("Family sides", value: "\(payload.branches.count)")
                        LabeledContent("Folders", value: "\(payload.folders.count)")
                        LabeledContent("Members", value: "\(payload.members.count)")

                        LabeledContent(
                                "Created",
                                value: payload.manifest.createdAt.formatted(date: .long, time: .shortened)
                            )
                    }

                    Section("Restore Passphrase") {
                        SecureField("Passphrase", text: $restorePassphrase)
                        if restorePassphrase.isEmpty {
                            Text("Using backup passphrase")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        Button {
                            confirmRestore(payload: payload)
                        } label: {
                            Label(
                                "Restore \(payload.letters.count) Letters",
                                systemImage: "arrow.down.doc.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(payload.letters.isEmpty && payload.children.isEmpty)
                    } footer: {
                        Text("This will add the restored content alongside your existing archive. Duplicate prevention will skip letters that already exist. Attachments are re-imported by their original identifiers.")
                    }
                }
                .navigationTitle("Restore Archive")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            restorePayload = nil
                            showingRestorePreview = false
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Preview",
                    systemImage: "doc.questionmark",
                    description: Text("The archive could not be read.")
                )
            }
        }
        .frame(minWidth: 480, minHeight: 500)
    }

    private func confirmRestore(payload: BackupPayload) {
        let pass = restorePassphrase.isEmpty ? passphrase : restorePassphrase
        guard !pass.isEmpty else {
            restoreProgress = "A passphrase is required."
            return
        }

        let persistence = PersistenceController.shared
        var imported = 0
        var skipped = 0

        // Restore children (skip duplicates by ID).
        let existingChildren = (try? context.fetch(
            NSFetchRequest<ChildProfile>(entityName: "ChildProfile")
        )) ?? []
        let existingChildIDs = Set(existingChildren.map(\.id))

        for child in payload.children {
            guard !existingChildIDs.contains(child.id) else { skipped += 1; continue }
            let entity = persistence.insertPrivate(ChildProfile.self, into: context)
            entity.id = child.id
            entity.name = child.name
            entity.birthDate = child.birthDate
            entity.createdAt = .now
            entity.updatedAt = .now
            imported += 1
        }

        // Restore letters (skip duplicates by ID).
        let existingLetters = (try? context.fetch(
            NSFetchRequest<Letter>(entityName: "Letter")
        )) ?? []
        let existingLetterIDs = Set(existingLetters.map(\.id))

        for letter in payload.letters {
            guard !existingLetterIDs.contains(letter.id) else { skipped += 1; continue }
            let entity = persistence.insertPrivate(Letter.self, into: context)
            entity.id = letter.id
            entity.childID = letter.childID
            entity.branchID = letter.branchID
            entity.folderID = letter.folderID
            entity.authorMemberID = letter.authorMemberID
            entity.title = letter.title
            entity.body = letter.body
            entity.authorName = letter.authorName
            entity.createdAt = letter.createdAt
            entity.updatedAt = letter.updatedAt
            entity.sealedAt = letter.sealedAt
            entity.isFavorite = letter.isFavorite
            entity.unlockRuleRawValue = letter.unlockRuleRawValue
            entity.unlockDate = letter.unlockDate
            entity.unlockAgeYears = letter.unlockAgeYearsValue
            entity.lifeEventName = letter.lifeEventName
            entity.manuallyReleasedAt = letter.manuallyReleasedAt
            imported += 1
        }

        try? persistence.save(context)
        restorePayload = nil
        showingRestorePreview = false
        restoreProgress = "Imported \(imported) records, skipped \(skipped) duplicates."
    }
}

// MARK: - History Row

private struct HistoryRow: View {
    @ObservedObject var record: BackupRecordEntity
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: record.destination.systemImage)
                .foregroundStyle(record.status == .completed ? .green : .red)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.destination.title)
                    .font(.subheadline)
                Text("\(record.createdAt.formatted(date: .numeric, time: .shortened)) · \(formatBytes(record.sizeBytes))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(record.letterCount) letters")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .contextMenu {
            Button("Delete Record", role: .destructive, action: onDelete)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}

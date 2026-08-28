import CoreData
import LettersToMyCore
import SwiftUI
import UniformTypeIdentifiers

struct BackupSettingsView: View {
    @Environment(\.managedObjectContext) private var context
    @StateObject private var backupManager = BackupServiceManager.shared

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
    @State private var showingRemoteRestorePicker = false
    @State private var remoteBackups: [BackupRemoteHandle] = []
    @State private var isListingRemote = false
    @State private var remoteListError: String?

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
        .sheet(isPresented: $showingRemoteRestorePicker) {
            remoteRestorePickerSheet
        }
    }

    // MARK: - Destinations

    private var destinationsSection: some View {
        Section("Destinations") {
            if backupManager.availableDestinations.isEmpty {
                Text("No backup destinations are configured yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(backupManager.availableDestinations, id: \.self) { destination in
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
            if passphrase.isEmpty {
                Text("Enter a passphrase above to enable backup.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
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

            if backupManager.availableDestinations.contains(.selfHosted) {
                Button {
                    Task { await listRemoteBackups() }
                } label: {
                    if isListingRemote {
                        Label("Checking Server…", systemImage: "ellipsis.circle")
                    } else {
                        Label("Restore from Self-Hosted Server", systemImage: "server.rack")
                    }
                }
                .disabled(isListingRemote)
            }

            if let remoteListError {
                Text(remoteListError)
                    .font(.footnote)
                    .foregroundStyle(.red)
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

        statusMessage = "\(destination.title) backup complete — \(record.letterCount) letters, \(record.sizeBytes.formattedBytes())."
        statusIsError = false
        AppAnalytics.backupCompleted(destination: destination.title, sizeBytes: record.sizeBytes)
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

    // MARK: - Self-hosted remote restore

    /// List the backups stored on the configured self-hosted server via the
    /// existing provider abstraction (the same provider used for backup).
    private func listRemoteBackups() async {
        guard let provider = service.provider(for: .selfHosted) else {
            remoteListError = "Self-hosted server is not configured."
            return
        }
        isListingRemote = true
        remoteListError = nil
        defer { isListingRemote = false }
        do {
            let handles = try await provider.listRemoteBackups()
            remoteBackups = handles.sorted { lhs, rhs in
                let lts = Int64(lhs.metadata["timestamp"] ?? "0") ?? 0
                let rts = Int64(rhs.metadata["timestamp"] ?? "0") ?? 0
                return lts > rts
            }
            if remoteBackups.isEmpty {
                remoteListError = "No backups found on the server."
            } else {
                showingRemoteRestorePicker = true
            }
        } catch {
            remoteListError = "Could not reach the server: \(error.localizedDescription)"
        }
    }

    /// Download a remote backup, decrypt it with the existing backup system,
    /// and hand the payload to the shared restore preview.
    private func downloadRemoteBackup(_ handle: BackupRemoteHandle) async {
        let pass = restorePassphrase.isEmpty ? passphrase : restorePassphrase
        guard !pass.isEmpty else {
            restoreProgress = "Enter a passphrase to restore this backup."
            return
        }
        restoreProgress = "Downloading and decrypting…"
        do {
            let payload = try await service.restore(
                from: .selfHosted,
                handle: handle,
                passphrase: pass
            )
            restorePayload = payload
            showingRemoteRestorePicker = false
            showingRestorePreview = true
            restoreProgress = ""
        } catch {
            restoreProgress = "Restore failed: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var remoteRestorePickerSheet: some View {
        NavigationStack {
            List {
                if remoteBackups.isEmpty {
                    ContentUnavailableView(
                        "No Remote Backups",
                        systemImage: "server.rack",
                        description: Text("No backups were found on the self-hosted server.")
                    )
                } else {
                    Section("Select a backup to restore") {
                        ForEach(remoteBackups, id: \.identifier) { handle in
                            Button {
                                Task { await downloadRemoteBackup(handle) }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(handle.identifier)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        if let timestamp = handle.metadata["timestamp"],
                                           let ms = Int64(timestamp) {
                                            Text(Date(timeIntervalSince1970: Double(ms) / 1000)
                                                .formatted(date: .abbreviated, time: .shortened))
                                        }
                                        if let size = handle.metadata["size"] {
                                            Text(ByteCountFormatter.string(fromByteCount: Int64(size) ?? 0, countStyle: .file))
                                        }
                                        if let letters = handle.metadata["letters"] {
                                            Text("\(letters) letters")
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Restore from Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingRemoteRestorePicker = false
                        remoteBackups = []
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 400)
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
            // The format payload does not carry child timestamps; preserve
            // the archive itself and stamp the restore time.
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

        // Restore attachments (skip duplicates by ID).
        let existingAttachments = (try? context.fetch(
            NSFetchRequest<LetterAttachment>(entityName: "LetterAttachment")
        )) ?? []
        let existingAttachmentIDs = Set(existingAttachments.map(\.id))

        // Letters available for linking (existing or just imported).
        let restoredLetters = (try? context.fetch(
            NSFetchRequest<Letter>(entityName: "Letter")
        )) ?? []
        let letterByID = Dictionary(uniqueKeysWithValues: restoredLetters.map { ($0.id, $0) })

        for attachment in payload.attachments {
            guard !existingAttachmentIDs.contains(attachment.id) else { skipped += 1; continue }
            let entity = persistence.insertPrivate(LetterAttachment.self, into: context)
            entity.id = attachment.id
            entity.letterID = attachment.letterID
            entity.fileName = attachment.fileName
            entity.contentTypeIdentifier = attachment.contentTypeIdentifier
            entity.kindRawValue = attachment.kindRawValue
            entity.createdAt = attachment.createdAt
            entity.data = attachment.data
            entity.letter = letterByID[attachment.letterID]
            imported += 1
        }

        // Restore branches (skip duplicates by ID) with matching partitions.
        let existingBranches = (try? context.fetch(
            NSFetchRequest<FamilyBranchRecord>(entityName: "FamilyBranchRecord")
        )) ?? []
        let existingBranchIDs = Set(existingBranches.map(\.id))

        for branch in payload.branches {
            guard !existingBranchIDs.contains(branch.id) else { skipped += 1; continue }
            let partition = persistence.insertPrivate(SharePartitionRecord.self, into: context)
            partition.kind = .branch
            partition.displayName = branch.name
            partition.scopeID = branch.id

            let entity = persistence.insertPrivate(FamilyBranchRecord.self, into: context)
            entity.id = branch.id
            entity.name = branch.name
            entity.kindRawValue = branch.kindRawValue
            entity.parentBranchID = branch.parentBranchID
            entity.partition = partition
            imported += 1
        }

        // Restore folders (skip duplicates by ID) with matching partitions.
        let existingFolders = (try? context.fetch(
            NSFetchRequest<ArchiveFolderRecord>(entityName: "ArchiveFolderRecord")
        )) ?? []
        let existingFolderIDs = Set(existingFolders.map(\.id))

        for folder in payload.folders {
            guard !existingFolderIDs.contains(folder.id) else { skipped += 1; continue }
            let partition = persistence.insertPrivate(SharePartitionRecord.self, into: context)
            partition.kind = .folder
            partition.displayName = folder.name
            partition.scopeID = folder.id

            let entity = persistence.insertPrivate(ArchiveFolderRecord.self, into: context)
            entity.id = folder.id
            entity.branchID = folder.branchID
            entity.parentFolderID = folder.parentFolderID
            entity.name = folder.name
            entity.partition = partition
            imported += 1
        }

        // Restore members (skip duplicates by ID) with archive partitions.
        let existingMembers = (try? context.fetch(
            NSFetchRequest<ArchiveMemberRecord>(entityName: "ArchiveMemberRecord")
        )) ?? []
        let existingMemberIDs = Set(existingMembers.map(\.id))

        for member in payload.members {
            guard !existingMemberIDs.contains(member.id) else { skipped += 1; continue }
            let partition = persistence.insertPrivate(SharePartitionRecord.self, into: context)
            partition.kind = .archiveAdministration
            partition.displayName = member.displayName

            let entity = persistence.insertPrivate(ArchiveMemberRecord.self, into: context)
            entity.id = member.id
            entity.displayName = member.displayName
            entity.relationship = member.relationship
            entity.roleRawValue = member.roleRawValue
            entity.statusRawValue = member.statusRawValue
            entity.canInviteOthers = member.canInviteOthers
            entity.partition = partition
            imported += 1
        }

        // Restore invitations (skip duplicates by ID) with partitions.
        let existingInvitations = (try? context.fetch(
            NSFetchRequest<CollaborationInvitationRecord>(entityName: "CollaborationInvitationRecord")
        )) ?? []
        let existingInvitationIDs = Set(existingInvitations.map(\.id))

        for invitation in payload.invitations {
            guard !existingInvitationIDs.contains(invitation.id) else { skipped += 1; continue }
            let partition = persistence.insertPrivate(SharePartitionRecord.self, into: context)
            partition.kind = .archiveAdministration
            partition.displayName = invitation.inviteeDisplayName

            let entity = persistence.insertPrivate(CollaborationInvitationRecord.self, into: context)
            entity.id = invitation.id
            entity.inviteeDisplayName = invitation.inviteeDisplayName
            entity.inviteeAddress = invitation.inviteeAddress
            entity.relationship = invitation.relationship
            entity.roleRawValue = invitation.roleRawValue
            entity.statusRawValue = invitation.statusRawValue
            entity.partition = partition
            imported += 1
        }

        try? persistence.save(context)

        // Restored letters that are already past their unlock rule need
        // deliveries; the same pipeline the app runs at launch handles
        // this idempotently (letters with an existing delivery are skipped).
        persistence.processPendingDeliveries(into: context)

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
                Text("\(record.createdAt.formatted(date: .numeric, time: .shortened)) · \(record.sizeBytes.formattedBytes())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(record.letterCount) letters")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
        }
        .contextMenu {
            Button("Delete Record", role: .destructive, action: onDelete)
        }
    }
}

private extension Int64 {
    func formattedBytes() -> String {
        if self < 1024 { return "\(self) B" }
        if self < 1_048_576 { return String(format: "%.1f KB", Double(self) / 1024) }
        return String(format: "%.1f MB", Double(self) / 1_048_576)
    }
}

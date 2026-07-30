import CloudKit
import CoreData
import LettersToMyCore
import SwiftUI

struct CollaboratorsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FamilyBranchRecord.createdAt, ascending: true)],
        animation: .default
    ) private var branchResults: FetchedResults<FamilyBranchRecord>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ArchiveFolderRecord.createdAt, ascending: true)],
        animation: .default
    ) private var folderResults: FetchedResults<ArchiveFolderRecord>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ArchiveMemberRecord.createdAt, ascending: true)],
        animation: .default
    ) private var memberResults: FetchedResults<ArchiveMemberRecord>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CollaborationInvitationRecord.createdAt, ascending: false)],
        animation: .default
    ) private var invitationResults: FetchedResults<CollaborationInvitationRecord>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChildProfile.createdAt, ascending: true)],
        animation: .default
    ) private var childResults: FetchedResults<ChildProfile>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SharePartitionRecord.createdAt, ascending: true)],
        animation: .default
    ) private var partitionResults: FetchedResults<SharePartitionRecord>

    @State private var sheet: EditorSheet?

    private var privateStore: NSPersistentStore? {
        PersistenceController.shared.privateStore
    }

    private var privateBranches: [FamilyBranchRecord] {
        guard let privateStore else { return [] }
        return branchResults.filter { $0.objectID.persistentStore === privateStore }
    }

    private var privateFolders: [ArchiveFolderRecord] {
        guard let privateStore else { return [] }
        return folderResults.filter { $0.objectID.persistentStore === privateStore }
    }

    private var privatePartitions: [SharePartitionRecord] {
        guard let privateStore else { return [] }
        return partitionResults.filter { $0.objectID.persistentStore === privateStore }
    }

    private var activeInvitations: [CollaborationInvitationRecord] {
        invitationResults.filter {
            [.pending, .delivered, .sent].contains($0.status)
        }
    }

    private var settledInvitations: [CollaborationInvitationRecord] {
        invitationResults.filter {
            [.accepted, .declined, .expired, .revoked, .failed].contains($0.status)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                FamilySidesSection(
                    branches: privateBranches,
                    folders: privateFolders
                )

                CollaboratorMembersSection(members: Array(memberResults))

                InvitationPlansSection(
                    activeInvitations: activeInvitations,
                    settledInvitations: settledInvitations,
                    branches: Array(branchResults),
                    folders: Array(folderResults),
                    children: Array(childResults),
                    partitions: privatePartitions
                )
            }
            .navigationTitle("People & Access")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) { EditButton() }
                #endif
                addMenu
            }
            .task {
                seedPrivateArchive()
                PersistenceController.shared.linkExistingSharesToInvitations(into: context)
            }
            .sheet(item: $sheet) { selectedSheet in
                editor(for: selectedSheet)
                    .environment(\.managedObjectContext, context)
            }
        }
    }

    @ToolbarContentBuilder
    private var addMenu: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Invite Person", systemImage: "person.badge.plus") {
                    sheet = .invite
                }
                Button("Add Family Side", systemImage: "point.3.connected.trianglepath.dotted") {
                    sheet = .branch
                }
                Button("Add Folder", systemImage: "folder.badge.plus") {
                    sheet = .folder
                }
                .disabled(privateBranches.isEmpty)
            } label: {
                Label("Add", systemImage: "plus")
                    .accessibilityLabel("Add people, family side, or folder")
            }
        }
    }

    @ViewBuilder
    private func editor(for selectedSheet: EditorSheet) -> some View {
        switch selectedSheet {
        case .invite:
            NavigationStack {
                InviteCollaboratorView(
                    branches: privateBranches,
                    folders: privateFolders,
                    children: Array(childResults),
                    partitions: privatePartitions
                )
            }
            .frame(minWidth: 480, minHeight: 600)

        case .branch:
            NavigationStack { AddBranchView() }
                .frame(minWidth: 420, minHeight: 340)

        case .folder:
            NavigationStack { AddFolderView(branches: privateBranches) }
                .frame(minWidth: 420, minHeight: 340)
        }
    }

    private func seedPrivateArchive() {
        let persistence = PersistenceController.shared

        if !privatePartitions.contains(where: { $0.kind == .archiveAdministration }) {
            let partition = persistence.insertPrivate(
                SharePartitionRecord.self,
                into: context
            )
            partition.kind = .archiveAdministration
            partition.displayName = "Family Archive Administration"
        }

        guard privateBranches.isEmpty else {
            try? persistence.save(context)
            return
        }

        let defaults: [(String, FamilyBranchKind)] = [
            ("Parents", .parents),
            ("Maternal Family", .maternal),
            ("Paternal Family", .paternal),
            ("Chosen Family", .chosenFamily)
        ]

        for (name, kind) in defaults {
            let partition = persistence.insertPrivate(
                SharePartitionRecord.self,
                into: context
            )
            partition.kind = .branch
            partition.displayName = name

            let branch = persistence.insertPrivate(
                FamilyBranchRecord.self,
                into: context
            )
            branch.name = name
            branch.kind = kind
            branch.isSeeded = true
            branch.partition = partition
            partition.scopeID = branch.id
        }

        try? persistence.save(context)
    }
}

private enum EditorSheet: String, Identifiable {
    case invite
    case branch
    case folder

    var id: String { rawValue }
}

private struct FamilySidesSection: View {
    @Environment(\.managedObjectContext) private var context
    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]

    var body: some View {
        Section("Family sides and folders") {
            ForEach(branches) { branch in
                let branchFolders = folders.filter { $0.branchID == branch.id }
                FamilyBranchRow(
                    branch: branch,
                    folders: branchFolders
                )

            }
            .onDelete { offsets in
                for index in offsets {
                    guard !branches[index].isSeeded else { continue }
                    context.delete(branches[index])
                }
                try? PersistenceController.shared.save(context)
            }
        }
    }
}

private struct FamilyBranchRow: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var branch: FamilyBranchRecord
    let folders: [ArchiveFolderRecord]

    var body: some View {
        DisclosureGroup {
            if folders.isEmpty {
                Text("No folders yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(folders) { folder in
                    HStack {
                        Label(folder.name, systemImage: "folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            context.delete(folder)
                            try? PersistenceController.shared.save(context)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        } label: {
            Label(branch.name, systemImage: branch.kind.systemImage)
        }
    }
}

private struct CollaboratorMembersSection: View {
    let members: [ArchiveMemberRecord]

    var body: some View {
        Section("Collaborators") {
            if members.isEmpty {
                ContentUnavailableView(
                    "No Active Collaborators",
                    systemImage: "person.2.badge.plus",
                    description: Text("Accepted family members will appear here with their role and scope.")
                )
            } else {
                ForEach(members) { member in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(member.displayName)
                            .font(.headline)
                        Text("\(member.relationship) · \(member.role.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct InvitationPlansSection: View {
    let activeInvitations: [CollaborationInvitationRecord]
    let settledInvitations: [CollaborationInvitationRecord]
    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]
    let children: [ChildProfile]
    let partitions: [SharePartitionRecord]

    var body: some View {
        Section {
            if activeInvitations.isEmpty && settledInvitations.isEmpty {
                Text("No invitations yet")
                    .foregroundStyle(.secondary)
            }

            ForEach(activeInvitations) { invitation in
                InvitationRow(
                    invitation: invitation,
                    branches: branches,
                    folders: folders,
                    children: children,
                    partitions: partitions
                )
            }

            if !settledInvitations.isEmpty {
                ForEach(settledInvitations) { invitation in
                    SettledInvitationRow(invitation: invitation)
                }
            }
        } header: {
            Text("Invitations")
        } footer: {
            if !activeInvitations.isEmpty {
                Text("Each Send button opens Apple's CloudKit sharing sheet. Parent/admin access can require several scoped shares so narrow family permissions remain enforceable.")
            }
        }
    }
}

private struct InvitationRow: View {
    @ObservedObject var invitation: CollaborationInvitationRecord
    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]
    let children: [ChildProfile]
    let partitions: [SharePartitionRecord]

    @State private var sharingPartition: SharePartitionRecord?
    @State private var showingRevokeConfirmation = false

    private var grants: [SharePartitionRecord] {
        let scope = invitation.scope

        let matches: [SharePartitionRecord]
        if scope.archiveWide && invitation.role == .parentAdmin {
            matches = partitions
        } else if scope.archiveWide {
            matches = partitions.filter { $0.kind == .archiveAdministration }
        } else if !scope.folderIDs.isEmpty {
            matches = partitions.filter {
                $0.kind == .folder && $0.scopeID.map(scope.folderIDs.contains) == true
            }
        } else if !scope.branchIDs.isEmpty {
            matches = partitions.filter {
                $0.kind == .branch && $0.scopeID.map(scope.branchIDs.contains) == true
            }
        } else if !scope.recipientIDs.isEmpty {
            matches = partitions.filter {
                $0.kind == .recipientInbox && $0.scopeID.map(scope.recipientIDs.contains) == true
            }
        } else {
            matches = invitation.partition.map { [$0] } ?? []
        }
        // Deduplicate by ID to prevent duplicate buttons if a
        // partition appears more than once in the matches array.
        var seen = Set<UUID>()
        return matches.filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(invitation.inviteeDisplayName)
                    .font(.headline)
                Spacer()
                HStack(spacing: 6) {
                    Text(invitation.status.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(invitation.status.color, in: Capsule())
                    Text(invitation.role.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }

            Text("\(invitation.relationship) · \(scopeSummary)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(invitation.inviteeAddress)
                .font(.caption)
                .foregroundStyle(.tertiary)

            if grants.isEmpty {
                Label(
                    "No share partition is available for this plan",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                ForEach(grants) { partition in
                    Button {
                        sharingPartition = partition
                    } label: {
                        Label(
                            "Send \(partition.displayName)",
                            systemImage: "icloud.and.arrow.up"
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }

            HStack {
                Spacer()
                if invitation.status == .declined || invitation.status == .expired || invitation.status == .failed {
                    Button("Resend Invitation") {
                        invitation.status = .pending
                        try? PersistenceController.shared.save()
                    }
                    .font(.caption)
                }
                Button("Revoke Invitation", role: .destructive) {
                    showingRevokeConfirmation = true
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 5)
        .confirmationDialog(
            "Revoke this invitation? \(invitation.inviteeDisplayName) will lose access to the shared content.",
            isPresented: $showingRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) { revoke() }
            Button("Cancel", role: .cancel) {}
        }
        #if os(iOS)
        .sheet(item: $sharingPartition) { partition in
            CloudSharingView(partition: partition) { share in
                if let share {
                    invitation.markSent(ckShareRecordName: share.recordID.recordName)
                    try? PersistenceController.shared.save()
                    Analytics.invitationSent()
                }
                sharingPartition = nil
            }
        }
        #endif
    }

    private var scopeSummary: String {
        let scope = invitation.scope
        if scope.archiveWide { return "Entire archive" }

        if let recipientID = scope.recipientIDs.first,
           let child = children.first(where: { $0.id == recipientID }) {
            return "Recipient: \(child.name)"
        }

        if let folderID = scope.folderIDs.first,
           let folder = folders.first(where: { $0.id == folderID }) {
            return "Folder: \(folder.name)"
        }

        if let branchID = scope.branchIDs.first,
           let branch = branches.first(where: { $0.id == branchID }) {
            return branch.name
        }

        return "No scope selected"
    }

    private func revoke() {
        invitation.markRevoked()
        invitation.partition?.memberActivationData = nil
        try? PersistenceController.shared.save()
        Analytics.invitationRevoked()
    }
}

/// A compact row for invitations whose lifecycle is complete:
/// accepted, declined, expired, revoked, or failed.
private struct SettledInvitationRow: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var invitation: CollaborationInvitationRecord

    var body: some View {
        HStack {
            Image(systemName: invitation.status.systemImage)
                .foregroundStyle(invitation.status.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.inviteeDisplayName)
                    .font(.subheadline)
                Text("\(invitation.relationship) · \(invitation.status.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(invitation.role.title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button {
                context.delete(invitation)
                try? PersistenceController.shared.save(context)
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
        .opacity(0.6)
    }
}

private struct AddBranchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var name = ""
    @State private var kind = FamilyBranchKind.custom

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Type", selection: $kind) {
                ForEach(FamilyBranchKind.allCases, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
        }
        .navigationTitle("New Family Side")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: add)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func add() {
        let persistence = PersistenceController.shared
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let partition = persistence.insertPrivate(
            SharePartitionRecord.self,
            into: context
        )
        partition.kind = .branch
        partition.displayName = trimmedName

        let branch = persistence.insertPrivate(
            FamilyBranchRecord.self,
            into: context
        )
        branch.name = trimmedName
        branch.kind = kind
        branch.partition = partition
        partition.scopeID = branch.id

        try? persistence.save(context)
        dismiss()
    }
}

private struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    let branches: [FamilyBranchRecord]

    @State private var name = ""
    @State private var branchID: UUID?

    var body: some View {
        Form {
            TextField("Folder name", text: $name)
            Picker("Family side", selection: $branchID) {
                Text("Choose a side").tag(nil as UUID?)
                ForEach(branches) { branch in
                    Text(branch.name).tag(branch.id as UUID?)
                }
            }
        }
        .navigationTitle("New Folder")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add", action: add)
                    .disabled(
                        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || branchID == nil
                    )
            }
        }
    }

    private func add() {
        guard let branchID else { return }

        let persistence = PersistenceController.shared
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let partition = persistence.insertPrivate(
            SharePartitionRecord.self,
            into: context
        )
        partition.kind = .folder
        partition.displayName = trimmedName

        let folder = persistence.insertPrivate(
            ArchiveFolderRecord.self,
            into: context
        )
        folder.branchID = branchID
        folder.name = trimmedName
        folder.partition = partition
        partition.scopeID = folder.id

        try? persistence.save(context)
        dismiss()
    }
}

private struct InviteCollaboratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]
    let children: [ChildProfile]
    let partitions: [SharePartitionRecord]

    @State private var displayName = ""
    @State private var address = ""
    @State private var relationship = ""
    @State private var role = CollaborationRole.contributor
    @State private var scopeKind = InviteScopeKind.branch
    @State private var branchID: UUID?
    @State private var folderID: UUID?
    @State private var recipientID: UUID?
    @State private var canInviteOthers = false

    private var availableFolders: [ArchiveFolderRecord] {
        guard let branchID else { return folders }
        return folders.filter { $0.branchID == branchID }
    }

    var body: some View {
        Form {
            personSection
            roleSection
            scopeSection
        }
        .navigationTitle(role == .recipient ? "Invite Recipient" : "Invite Collaborator")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Invitation", action: save)
                    .disabled(!isValid)
            }
        }
    }

    private var personSection: some View {
        Section("Person") {
            TextField("Name", text: $displayName)
            TextField("Email or phone", text: $address)
            TextField(
                "Relationship",
                text: $relationship,
                prompt: Text("Grandmother, spouse, family friend…")
            )
        }
    }

    private var roleSection: some View {
        Section("Role") {
            Picker("Role", selection: $role) {
                ForEach(CollaborationRole.allCases.filter { $0 != .owner }, id: \.self) {
                    Text($0.title).tag($0)
                }
            }
            .onChange(of: role) { _, newRole in
                scopeKind = newRole == .recipient
                    ? .recipient
                    : (newRole == .parentAdmin ? .archive : .branch)
            }

            Text(role.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if role == .parentAdmin || role == .organizer {
                Toggle("Can invite other people", isOn: $canInviteOthers)
            }
        }
    }

    @ViewBuilder
    private var scopeSection: some View {
        Section("Access scope") {
            Picker("Scope", selection: $scopeKind) {
                ForEach(InviteScopeKind.allowed(for: role), id: \.self) {
                    Text($0.title).tag($0)
                }
            }

            switch scopeKind {
            case .archive:
                Text("The invitation will provide separate CloudKit shares for every current archive partition.")
                    .foregroundStyle(.secondary)

            case .branch:
                branchPicker(title: "Family side")

            case .folder:
                branchPicker(title: "Family side")
                Picker("Folder", selection: $folderID) {
                    Text("Choose a folder").tag(nil as UUID?)
                    ForEach(availableFolders) { folder in
                        Text(folder.name).tag(folder.id as UUID?)
                    }
                }

            case .recipient:
                Picker("Recipient", selection: $recipientID) {
                    Text("Choose a recipient").tag(nil as UUID?)
                    ForEach(children) { child in
                        Text(child.name.isEmpty ? "Unnamed child" : child.name)
                            .tag(child.id as UUID?)
                    }
                }
            }
        }
    }

    private func branchPicker(title: String) -> some View {
        Picker(title, selection: $branchID) {
            Text("Choose a side").tag(nil as UUID?)
            ForEach(branches) { branch in
                Text(branch.name).tag(branch.id as UUID?)
            }
        }
    }

    private var isValid: Bool {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch scopeKind {
        case .archive:
            return true
        case .branch:
            return branchID != nil
        case .folder:
            return folderID != nil
        case .recipient:
            return recipientID != nil
        }
    }

    private func save() {
        let scope: CollaborationScope
        let partition: SharePartitionRecord?

        switch scopeKind {
        case .archive:
            scope = .archive
            partition = partitions.first { $0.kind == .archiveAdministration }

        case .branch:
            scope = CollaborationScope(branchIDs: branchID.map { [$0] } ?? [])
            partition = branches.first { $0.id == branchID }?.partition

        case .folder:
            scope = CollaborationScope(
                branchIDs: branchID.map { [$0] } ?? [],
                folderIDs: folderID.map { [$0] } ?? []
            )
            partition = folders.first { $0.id == folderID }?.partition

        case .recipient:
            scope = CollaborationScope(recipientIDs: recipientID.map { [$0] } ?? [])
            partition = children.first { $0.id == recipientID }?.partition
        }

        let invitation = PersistenceController.shared.insertPrivate(
            CollaborationInvitationRecord.self,
            into: context
        )
        invitation.inviteeDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        invitation.inviteeAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        invitation.relationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        invitation.role = role
        invitation.scope = scope
        invitation.intendedRecipientID = role == .recipient ? recipientID : nil
        invitation.canInviteOthers = canInviteOthers
        invitation.partition = partition
        invitation.intendedMemberID = UUID()

        // Embed the member activation metadata in the target partition so the
        // invitee can create a correct local ArchiveMemberRecord after
        // acceptance without relying on the inviter's private store.
        let activation = invitation.prepareMemberActivation()
        partition?.memberActivation = activation

        try? PersistenceController.shared.save(context)
        dismiss()
    }
}

private enum InviteScopeKind: String, CaseIterable {
    case archive
    case branch
    case folder
    case recipient

    var title: String {
        switch self {
        case .archive: "Entire archive"
        case .branch: "Family side"
        case .folder: "Specific folder"
        case .recipient: "Recipient inbox"
        }
    }

    static func allowed(for role: CollaborationRole) -> [InviteScopeKind] {
        switch role {
        case .owner: [.archive]
        case .parentAdmin: [.archive, .branch, .folder]
        case .organizer, .contributor, .viewer: [.branch, .folder]
        case .recipient: [.recipient]
        }
    }
}

private extension FamilyBranchKind {
    var systemImage: String {
        switch self {
        case .parents: "house.fill"
        case .maternal, .paternal: "person.2.fill"
        case .chosenFamily: "heart.fill"
        case .custom: "point.3.connected.trianglepath.dotted"
        }
    }
}

private extension CollaborationRole {
    var explanation: String {
        switch self {
        case .owner: "Controls the archive and can transfer ownership."
        case .parentAdmin: "A spouse, co-parent, or guardian who can administer the archive."
        case .organizer: "Can organize folders and manage content inside assigned family sides."
        case .contributor: "Can create content and manage only their own contributions inside assigned scopes."
        case .viewer: "Can read visible content but cannot edit it."
        case .recipient: "Can read only their own unlocked deliveries and optionally reply."
        }
    }
}

private extension InvitationStatus {
    var color: Color {
        switch self {
        case .pending: .orange
        case .delivered: .blue
        case .sent: .blue
        case .accepted: .green
        case .declined: .red
        case .expired: .gray
        case .revoked: .red
        case .failed: .red
        }
    }

    var systemImage: String {
        switch self {
        case .pending: "clock"
        case .delivered: "paperplane"
        case .sent: "paperplane.fill"
        case .accepted: "checkmark.circle.fill"
        case .declined: "xmark.circle.fill"
        case .expired: "hourglass.tophalf.filled"
        case .revoked: "person.fill.xmark"
        case .failed: "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Cloud Sharing View

#if os(iOS)
private struct CloudSharingView: View {
    let partition: SharePartitionRecord
    let onCompletion: (CKShare?) -> Void

    @State private var preparedShare: CKShare?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let share = preparedShare {
                CloudSharingController(
                    share: share,
                    container: PersistenceController.shared.ckContainer,
                    onCompletion: onCompletion
                )
            } else if let errorMessage {
                VStack(spacing: 16) {
                    Text("Could Not Create Share")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Dismiss") { onCompletion(nil) }
                        .buttonStyle(.bordered)
                }
                .padding()
            } else {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Preparing share…")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            do {
                let persistence = PersistenceController.shared
                preparedShare = try await persistence.prepareShare(
                    for: partition.objectID.uriRepresentation(),
                    title: partition.displayName
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CloudSharingController: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let onCompletion: (CKShare?) -> Void

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let onCompletion: (CKShare?) -> Void

        init(onCompletion: @escaping (CKShare?) -> Void) {
            self.onCompletion = onCompletion
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            onCompletion(csc.share)
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onCompletion(nil)
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onCompletion(nil)
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            csc.share?[CKShare.SystemFieldKey.title] as? String
        }
    }
}
#endif

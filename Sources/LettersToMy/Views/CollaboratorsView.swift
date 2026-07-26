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

    private var pendingInvitations: [CollaborationInvitationRecord] {
        invitationResults.filter { $0.status == .pending }
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
                    invitations: pendingInvitations,
                    branches: Array(branchResults),
                    folders: Array(folderResults),
                    children: Array(childResults),
                    partitions: privatePartitions
                )
            }
            .navigationTitle("People & Access")
            .toolbar { addMenu }
            .task { seedPrivateArchive() }
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
    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]

    var body: some View {
        Section("Family sides and folders") {
            ForEach(branches) { branch in
                FamilyBranchRow(
                    branch: branch,
                    folders: folders.filter { $0.branchID == branch.id }
                )
            }
        }
    }
}

private struct FamilyBranchRow: View {
    @ObservedObject var branch: FamilyBranchRecord
    let folders: [ArchiveFolderRecord]

    var body: some View {
        DisclosureGroup {
            if folders.isEmpty {
                Text("No folders yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(folders) { folder in
                    Label(folder.name, systemImage: "folder")
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
    let invitations: [CollaborationInvitationRecord]
    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]
    let children: [ChildProfile]
    let partitions: [SharePartitionRecord]

    var body: some View {
        Section {
            if invitations.isEmpty {
                Text("No pending invitations")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(invitations) { invitation in
                    InvitationRow(
                        invitation: invitation,
                        branches: branches,
                        folders: folders,
                        children: children,
                        partitions: partitions
                    )
                }
            }
        } header: {
            Text("Invitations")
        } footer: {
            Text("Each Send button opens Apple's CloudKit sharing sheet. Parent/admin access can require several scoped shares so narrow family permissions remain enforceable.")
        }
    }
}

private struct InvitationRow: View {
    @ObservedObject var invitation: CollaborationInvitationRecord
    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]
    let children: [ChildProfile]
    let partitions: [SharePartitionRecord]

    private var grants: [SharePartitionRecord] {
        let scope = invitation.scope

        if scope.archiveWide && invitation.role == .parentAdmin {
            return partitions
        }
        if scope.archiveWide {
            return partitions.filter { $0.kind == .archiveAdministration }
        }
        if !scope.folderIDs.isEmpty {
            return partitions.filter {
                $0.kind == .folder && $0.scopeID.map(scope.folderIDs.contains) == true
            }
        }
        if !scope.branchIDs.isEmpty {
            return partitions.filter {
                $0.kind == .branch && $0.scopeID.map(scope.branchIDs.contains) == true
            }
        }
        if !scope.recipientIDs.isEmpty {
            return partitions.filter {
                $0.kind == .recipientInbox && $0.scopeID.map(scope.recipientIDs.contains) == true
            }
        }
        return invitation.partition.map { [$0] } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(invitation.inviteeDisplayName)
                    .font(.headline)
                Spacer()
                Text(invitation.role.title)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
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
                    ShareLink(
                        item: partition.cloudShareItem,
                        preview: SharePreview(partition.displayName)
                    ) {
                        Label(
                            "Send \(partition.displayName)",
                            systemImage: "icloud.and.arrow.up"
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.vertical, 5)
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

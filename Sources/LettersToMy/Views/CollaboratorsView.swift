import CoreData
import LettersToMyCore
import SwiftUI

struct CollaboratorsView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FamilyBranchRecord.createdAt, ascending: true)],
        animation: .default
    ) private var branches: FetchedResults<FamilyBranchRecord>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ArchiveFolderRecord.createdAt, ascending: true)],
        animation: .default
    ) private var folders: FetchedResults<ArchiveFolderRecord>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ArchiveMemberRecord.createdAt, ascending: true)],
        animation: .default
    ) private var members: FetchedResults<ArchiveMemberRecord>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CollaborationInvitationRecord.createdAt, ascending: false)],
        animation: .default
    ) private var invitations: FetchedResults<CollaborationInvitationRecord>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChildProfile.createdAt, ascending: true)],
        animation: .default
    ) private var children: FetchedResults<ChildProfile>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SharePartitionRecord.createdAt, ascending: true)],
        animation: .default
    ) private var partitions: FetchedResults<SharePartitionRecord>

    @State private var showingInvite = false
    @State private var showingBranchEditor = false
    @State private var showingFolderEditor = false

    private var privateBranches: [FamilyBranchRecord] {
        branches.filter { $0.objectID.persistentStore === PersistenceController.shared.privateStore }
    }

    private var privateFolders: [ArchiveFolderRecord] {
        folders.filter { $0.objectID.persistentStore === PersistenceController.shared.privateStore }
    }

    private var privatePartitions: [SharePartitionRecord] {
        partitions.filter { $0.objectID.persistentStore === PersistenceController.shared.privateStore }
    }

    private var pendingInvitations: [CollaborationInvitationRecord] {
        invitations.filter { $0.status == .pending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Family sides and folders") {
                    ForEach(privateBranches) { branch in
                        DisclosureGroup {
                            let branchFolders = privateFolders.filter { $0.branchID == branch.id }
                            if branchFolders.isEmpty {
                                Text("No folders yet")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(branchFolders) { folder in
                                    Label(folder.name, systemImage: "folder")
                                }
                            }
                        } label: {
                            Label(branch.name, systemImage: branch.kind.systemImage)
                        }
                    }
                }

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

                Section("Invitations") {
                    if pendingInvitations.isEmpty {
                        Text("No pending invitations")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingInvitations) { invitation in
                            InvitationRow(
                                invitation: invitation,
                                branches: Array(branches),
                                folders: Array(folders),
                                children: Array(children),
                                partitions: privatePartitions
                            )
                        }
                    }
                } footer: {
                    Text("Each Send button opens Apple's CloudKit sharing sheet. Archive-wide parent/admin access can require more than one scoped share so narrow family permissions remain enforceable.")
                }
            }
            .navigationTitle("People & Access")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingInvite = true
                        } label: {
                            Label("Invite Person", systemImage: "person.badge.plus")
                        }

                        Button {
                            showingBranchEditor = true
                        } label: {
                            Label("Add Family Side", systemImage: "point.3.connected.trianglepath.dotted")
                        }

                        Button {
                            showingFolderEditor = true
                        } label: {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                        .disabled(privateBranches.isEmpty)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .task { seedPrivateArchive() }
            .sheet(isPresented: $showingInvite) {
                NavigationStack {
                    InviteCollaboratorView(
                        branches: privateBranches,
                        folders: privateFolders,
                        children: Array(children),
                        partitions: privatePartitions
                    )
                }
                .environment(\.managedObjectContext, managedObjectContext)
                .frame(minWidth: 480, minHeight: 600)
            }
            .sheet(isPresented: $showingBranchEditor) {
                NavigationStack { AddBranchView() }
                    .environment(\.managedObjectContext, managedObjectContext)
                    .frame(minWidth: 420, minHeight: 340)
            }
            .sheet(isPresented: $showingFolderEditor) {
                NavigationStack { AddFolderView(branches: privateBranches) }
                    .environment(\.managedObjectContext, managedObjectContext)
                    .frame(minWidth: 420, minHeight: 340)
            }
        }
    }

    private func seedPrivateArchive() {
        let persistence = PersistenceController.shared
        var archivePartition = privatePartitions.first(where: { $0.kind == .archiveAdministration })
        if archivePartition == nil {
            let created = persistence.insertPrivate(
                SharePartitionRecord.self,
                into: managedObjectContext
            )
            created.kind = .archiveAdministration
            created.displayName = "Family Archive Administration"
            archivePartition = created
        }

        guard privateBranches.isEmpty else {
            try? persistence.save(managedObjectContext)
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
                into: managedObjectContext
            )
            partition.kind = .branch
            partition.displayName = name

            let branch = persistence.insertPrivate(
                FamilyBranchRecord.self,
                into: managedObjectContext
            )
            branch.name = name
            branch.kind = kind
            partition.scopeID = branch.id
            branch.partition = partition
        }
        try? persistence.save(managedObjectContext)
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
            return partitions.filter { $0.kind == .folder && $0.scopeID.map(scope.folderIDs.contains) == true }
        }
        if !scope.branchIDs.isEmpty {
            return partitions.filter { $0.kind == .branch && $0.scopeID.map(scope.branchIDs.contains) == true }
        }
        if !scope.recipientIDs.isEmpty {
            return partitions.filter { $0.kind == .recipientInbox && $0.scopeID.map(scope.recipientIDs.contains) == true }
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
                Label("No share partition is available for this plan", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                ForEach(grants) { partition in
                    ShareLink(
                        item: partition.cloudShareItem,
                        preview: SharePreview(partition.displayName)
                    ) {
                        Label("Send \(partition.displayName)", systemImage: "icloud.and.arrow.up")
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
    @Environment(\.managedObjectContext) private var managedObjectContext

    @State private var name = ""
    @State private var kind = FamilyBranchKind.custom

    var body: some View {
        Form {
            TextField("Name", text: $name)
            Picker("Type", selection: $kind) {
                ForEach(FamilyBranchKind.allCases, id: \.self) { kind in
                    Text(kind.title).tag(kind)
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
        let partition = persistence.insertPrivate(
            SharePartitionRecord.self,
            into: managedObjectContext
        )
        partition.kind = .branch
        partition.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let branch = persistence.insertPrivate(
            FamilyBranchRecord.self,
            into: managedObjectContext
        )
        branch.name = partition.displayName
        branch.kind = kind
        branch.partition = partition
        partition.scopeID = branch.id
        try? persistence.save(managedObjectContext)
        dismiss()
    }
}

private struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext

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
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || branchID == nil)
            }
        }
    }

    private func add() {
        guard let branchID else { return }
        let persistence = PersistenceController.shared
        let partition = persistence.insertPrivate(
            SharePartitionRecord.self,
            into: managedObjectContext
        )
        partition.kind = .folder
        partition.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        let folder = persistence.insertPrivate(
            ArchiveFolderRecord.self,
            into: managedObjectContext
        )
        folder.branchID = branchID
        folder.name = partition.displayName
        folder.partition = partition
        partition.scopeID = folder.id
        try? persistence.save(managedObjectContext)
        dismiss()
    }
}

private struct InviteCollaboratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext

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
            Section("Person") {
                TextField("Name", text: $displayName)
                TextField("Email or phone", text: $address)
                TextField("Relationship", text: $relationship, prompt: Text("Grandmother, spouse, family friend…"))
            }

            Section("Role") {
                Picker("Role", selection: $role) {
                    ForEach(CollaborationRole.allCases.filter { $0 != .owner }, id: \.self) { role in
                        Text(role.title).tag(role)
                    }
                }
                .onChange(of: role) { _, newRole in
                    scopeKind = newRole == .recipient ? .recipient : (newRole == .parentAdmin ? .archive : .branch)
                }

                Text(role.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if role == .parentAdmin || role == .organizer {
                    Toggle("Can invite other people", isOn: $canInviteOthers)
                }
            }

            Section("Access scope") {
                Picker("Scope", selection: $scopeKind) {
                    ForEach(InviteScopeKind.allowed(for: role), id: \.self) { scope in
                        Text(scope.title).tag(scope)
                    }
                }

                switch scopeKind {
                case .archive:
                    Text("The invitation will provide separate CloudKit shares for every current archive partition.")
                        .foregroundStyle(.secondary)
                case .branch:
                    Picker("Family side", selection: $branchID) {
                        Text("Choose a side").tag(nil as UUID?)
                        ForEach(branches) { branch in
                            Text(branch.name).tag(branch.id as UUID?)
                        }
                    }
                case .folder:
                    Picker("Family side", selection: $branchID) {
                        Text("Any side").tag(nil as UUID?)
                        ForEach(branches) { branch in
                            Text(branch.name).tag(branch.id as UUID?)
                        }
                    }
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
                            Text(child.name.isEmpty ? "Unnamed child" : child.name).tag(child.id as UUID?)
                        }
                    }
                }
            }
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

    private var isValid: Bool {
        guard !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch scopeKind {
        case .archive: return true
        case .branch: return branchID != nil
        case .folder: return folderID != nil
        case .recipient: return recipientID != nil
        }
    }

    private func save() {
        let scope: CollaborationScope
        let partition: SharePartitionRecord?
        switch scopeKind {
        case .archive:
            scope = .archive
            partition = partitions.first(where: { $0.kind == .archiveAdministration })
        case .branch:
            scope = CollaborationScope(branchIDs: branchID.map { [$0] } ?? [])
            partition = branches.first(where: { $0.id == branchID })?.partition
        case .folder:
            scope = CollaborationScope(
                branchIDs: branchID.map { [$0] } ?? [],
                folderIDs: folderID.map { [$0] } ?? []
            )
            partition = folders.first(where: { $0.id == folderID })?.partition
        case .recipient:
            scope = CollaborationScope(recipientIDs: recipientID.map { [$0] } ?? [])
            partition = children.first(where: { $0.id == recipientID })?.partition
        }

        let invitation = PersistenceController.shared.insertPrivate(
            CollaborationInvitationRecord.self,
            into: managedObjectContext
        )
        invitation.inviteeDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        invitation.inviteeAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        invitation.relationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        invitation.role = role
        invitation.scope = scope
        invitation.intendedRecipientID = role == .recipient ? recipientID : nil
        invitation.canInviteOthers = canInviteOthers
        invitation.partition = partition
        try? PersistenceController.shared.save(managedObjectContext)
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

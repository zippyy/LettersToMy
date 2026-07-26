import LettersToMyCore
import SwiftData
import SwiftUI

struct CollaboratorsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyBranchRecord.createdAt) private var branches: [FamilyBranchRecord]
    @Query(sort: \ArchiveFolderRecord.createdAt) private var folders: [ArchiveFolderRecord]
    @Query(sort: \ArchiveMemberRecord.createdAt) private var members: [ArchiveMemberRecord]
    @Query(sort: \CollaborationInvitationRecord.createdAt, order: .reverse) private var invitations: [CollaborationInvitationRecord]
    @Query(sort: \ChildProfile.createdAt) private var children: [ChildProfile]

    @State private var showingInvite = false
    @State private var showingBranchEditor = false
    @State private var showingFolderEditor = false

    private var pendingInvitations: [CollaborationInvitationRecord] {
        invitations.filter { $0.status == .pending }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Family sides and folders") {
                    ForEach(branches) { branch in
                        DisclosureGroup {
                            let branchFolders = folders.filter { $0.branchID == branch.id }
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

                Section("Invitation plans") {
                    if pendingInvitations.isEmpty {
                        Text("No pending invitations")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pendingInvitations) { invitation in
                            InvitationRow(
                                invitation: invitation,
                                branches: branches,
                                folders: folders,
                                children: children
                            )
                        }
                    }
                } footer: {
                    Text("Invitation plans are saved locally. Sending and accepting the private iCloud share becomes active after the shared CloudKit store migration.")
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
                        .disabled(branches.isEmpty)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                }
            }
            .task { seedDefaultBranches() }
            .sheet(isPresented: $showingInvite) {
                NavigationStack {
                    InviteCollaboratorView(
                        branches: branches,
                        folders: folders,
                        children: children
                    )
                }
                .frame(minWidth: 480, minHeight: 600)
            }
            .sheet(isPresented: $showingBranchEditor) {
                NavigationStack { AddBranchView() }
                    .frame(minWidth: 420, minHeight: 340)
            }
            .sheet(isPresented: $showingFolderEditor) {
                NavigationStack { AddFolderView(branches: branches) }
                    .frame(minWidth: 420, minHeight: 340)
            }
        }
    }

    private func seedDefaultBranches() {
        guard branches.isEmpty else { return }
        let defaults: [(String, FamilyBranchKind)] = [
            ("Parents", .parents),
            ("Maternal Family", .maternal),
            ("Paternal Family", .paternal),
            ("Chosen Family", .chosenFamily)
        ]
        for (name, kind) in defaults {
            modelContext.insert(FamilyBranchRecord(name: name, kind: kind))
        }
        try? modelContext.save()
    }
}

private struct InvitationRow: View {
    let invitation: CollaborationInvitationRecord
    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]
    let children: [ChildProfile]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
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
        }
        .padding(.vertical, 3)
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
    @Environment(\.modelContext) private var modelContext

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
                Button("Add") {
                    modelContext.insert(FamilyBranchRecord(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        kind: kind
                    ))
                    try? modelContext.save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct AddFolderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

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
                Button("Add") {
                    guard let branchID else { return }
                    modelContext.insert(ArchiveFolderRecord(
                        branchID: branchID,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    try? modelContext.save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || branchID == nil)
            }
        }
    }
}

private struct InviteCollaboratorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let branches: [FamilyBranchRecord]
    let folders: [ArchiveFolderRecord]
    let children: [ChildProfile]

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
                    Text("Access applies across the complete family archive.")
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

            Section {
                Text("This creates the role and scope plan now. The private iCloud invitation will use the same plan after the shared-store migration is complete.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(role == .recipient ? "Invite Recipient" : "Invite Collaborator")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Invite Plan") { save() }
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
        switch scopeKind {
        case .archive:
            scope = .archive
        case .branch:
            scope = CollaborationScope(branchIDs: branchID.map { [$0] } ?? [])
        case .folder:
            scope = CollaborationScope(
                branchIDs: branchID.map { [$0] } ?? [],
                folderIDs: folderID.map { [$0] } ?? []
            )
        case .recipient:
            scope = CollaborationScope(recipientIDs: recipientID.map { [$0] } ?? [])
        }

        modelContext.insert(CollaborationInvitationRecord(
            inviteeDisplayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            inviteeAddress: address.trimmingCharacters(in: .whitespacesAndNewlines),
            relationship: relationship.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role,
            scope: scope,
            intendedRecipientID: role == .recipient ? recipientID : nil,
            canInviteOthers: canInviteOthers
        ))
        try? modelContext.save()
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
        case .owner:
            return [.archive]
        case .parentAdmin:
            return [.archive, .branch, .folder]
        case .organizer, .contributor, .viewer:
            return [.branch, .folder]
        case .recipient:
            return [.recipient]
        }
    }
}

private extension FamilyBranchKind {
    var systemImage: String {
        switch self {
        case .parents: "house.fill"
        case .maternal: "person.2.fill"
        case .paternal: "person.2.fill"
        case .chosenFamily: "heart.fill"
        case .custom: "point.3.connected.trianglepath.dotted"
        }
    }
}

private extension CollaborationRole {
    var explanation: String {
        switch self {
        case .owner:
            return "Controls the archive and can transfer ownership."
        case .parentAdmin:
            return "A spouse, co-parent, or guardian who can administer the archive."
        case .organizer:
            return "Can organize folders and manage content inside assigned family sides."
        case .contributor:
            return "Can create content and manage only their own contributions inside assigned scopes."
        case .viewer:
            return "Can read visible content but cannot edit it."
        case .recipient:
            return "Can read only their own unlocked deliveries and optionally reply."
        }
    }
}

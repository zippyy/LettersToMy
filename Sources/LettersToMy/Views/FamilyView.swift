import CoreData
import SwiftUI

struct FamilyView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChildProfile.createdAt, ascending: true)],
        animation: .default
    ) private var children: FetchedResults<ChildProfile>

    @State private var selectedChildID: UUID?
    @State private var showingAdd = false
    @State private var childPendingDeletion: ChildProfile?

    private var selectedChild: ChildProfile? {
        children.first { $0.id == selectedChildID } ?? children.first
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Recipients") {
                    if children.isEmpty {
                        ContentUnavailableView(
                            "No Children Yet",
                            systemImage: "figure.2.and.child.holdinghands",
                            description: Text("Add a child to start writing letters for their future.")
                        )
                    } else {
                        ForEach(children) { child in
                            ChildRow(
                                child: child,
                                isSelected: child.id == selectedChild?.id,
                                onSelect: { selectedChildID = child.id }
                            )
                        }
                        .onDelete(perform: deleteChildren)
                    }
                }

                if let child = selectedChild {
                    Section("\(child.name.isEmpty ? "Recipient" : child.name)'s Profile") {
                        EditChildView(child: child)
                    }
                }
            }
            .navigationTitle("Family")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Label("Add Child", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack {
                    AddChildView()
                }
                .frame(minWidth: 420, minHeight: 340)
            }
            .confirmationDialog(
                "Delete \\(childPendingDeletionName)?",
                isPresented: Binding(
                    get: { childPendingDeletion != nil },
                    set: { if !$0 { childPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Letters and Deliveries", role: .destructive) {
                    if let child = childPendingDeletion {
                        confirmDelete(child)
                    }
                    childPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    childPendingDeletion = nil
                }
            }
            .alert(
                "Recipient Deleted",
                isPresented: Binding(
                    get: { deletionSummary != nil },
                    set: { if !$0 { deletionSummary = nil } }
                )
            ) {
                Button("OK") { deletionSummary = nil }
            } message: {
                Text(deletionSummary ?? "")
            }
            .onAppear {
                if selectedChildID == nil {
                    selectedChildID = children.first?.id
                }
            }
        }
    }

    private func deleteChildren(at offsets: IndexSet) {
        for index in offsets {
            childPendingDeletion = children[index]
        }
    }

    private var childPendingDeletionName: String {
        guard let name = childPendingDeletion?.name, !name.isEmpty else { return "this recipient" }
        return name
    }

    private func confirmDelete(_ child: ChildProfile) {
        if selectedChildID == child.id {
            selectedChildID = nil
        }
        let result = PersistenceController.shared.deleteChild(child, in: managedObjectContext)
        if result.letters > 0 || result.deliveries > 0 {
            // Surface the cascade so the deletion is not silent.
            let parts = [
                result.letters > 0 ? "\\(result.letters) letters" : nil,
                result.deliveries > 0 ? "\\(result.deliveries) deliveries" : nil
            ].compactMap { $0 }
            deletionSummary = "Deleted " + parts.joined(separator: " and ") + " for \(child.name)."
        }
    }

    @State private var deletionSummary: String?
}

// MARK: - Child Row

private struct ChildRow: View {
    @ObservedObject var child: ChildProfile
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(child.name.isEmpty ? "Unnamed Child" : child.name)
                        .font(.headline)
                    if let birthDate = child.birthDate {
                        Text(birthDate, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Child

private struct EditChildView: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var child: ChildProfile

    @State private var name: String
    @State private var hasBirthDate: Bool
    @State private var birthDate: Date

    init(child: ChildProfile) {
        self.child = child
        _name = State(initialValue: child.name)
        _hasBirthDate = State(initialValue: child.birthDate != nil)
        _birthDate = State(initialValue: child.birthDate ?? .now)
    }

    var body: some View {
        Group {
            TextField("Name", text: $name)
            Toggle("Birth date is known", isOn: $hasBirthDate)
            if hasBirthDate {
                DatePicker(
                    "Birth date",
                    selection: $birthDate,
                    in: ...Date.now,
                    displayedComponents: .date
                )
            }
            Button("Save") { save() }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: name) { _, _ in autoSave() }
        .onChange(of: hasBirthDate) { _, _ in autoSave() }
        .onChange(of: birthDate) { _, _ in autoSave() }
    }

    private func autoSave() {
        save()
    }

    private func save() {
        let persistence = PersistenceController.shared
        child.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        child.birthDate = hasBirthDate ? birthDate : nil
        child.updatedAt = .now

        if child.partition == nil {
            let partition = persistence.insertPrivate(
                SharePartitionRecord.self,
                into: context
            )
            partition.kind = .recipientInbox
            partition.scopeID = child.id
            partition.displayName = "\(child.name)'s Recipient Inbox"
            child.partition = partition
        } else if !child.name.isEmpty {
            child.partition?.displayName = "\(child.name)'s Recipient Inbox"
            child.partition?.updatedAt = .now
        }

        try? persistence.save(context)
    }
}

// MARK: - Add Child

private struct AddChildView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var name = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date.now

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Toggle("Birth date is known", isOn: $hasBirthDate)
                if hasBirthDate {
                    DatePicker(
                        "Birth date",
                        selection: $birthDate,
                        in: ...Date.now,
                        displayedComponents: .date
                    )
                }
            } footer: {
                Text("The birth date is used only to calculate age-based letter unlocks and stays inside the private family archive.")
            }
        }
        .navigationTitle("Add Child")
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
        let child = persistence.insertPrivate(ChildProfile.self, into: context)
        child.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        child.birthDate = hasBirthDate ? birthDate : nil
        child.createdAt = .now
        child.updatedAt = .now

        let partition = persistence.insertPrivate(
            SharePartitionRecord.self,
            into: context
        )
        partition.kind = .recipientInbox
        partition.scopeID = child.id
        partition.displayName = "\(child.name.isEmpty ? "New Recipient" : child.name)'s Recipient Inbox"
        child.partition = partition

        try? persistence.save(context)
        dismiss()
    }
}

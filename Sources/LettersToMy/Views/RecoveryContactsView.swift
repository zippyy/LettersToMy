import CoreData
import SwiftUI

struct RecoveryContactsView: View {
    @Environment(\.managedObjectContext) private var context

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \RecoveryContactEntity.createdAt, ascending: true)],
        animation: .default
    ) private var contacts: FetchedResults<RecoveryContactEntity>

    @State private var showingAdd = false

    var body: some View {
        List {
            if contacts.isEmpty {
                ContentUnavailableView(
                    "No Recovery Contacts",
                    systemImage: "person.badge.key",
                    description: Text("Designate trusted people who can help recover the archive if you lose access. They do not gain access now — only through a defined recovery process.")
                )
            } else {
                ForEach(contacts) { contact in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(contact.displayName)
                            .font(.headline)
                        Text("\(contact.relationship) · \(contact.emailAddress)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let notes = contact.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onDelete(perform: deleteContacts)
            }
        }
        .navigationTitle("Recovery Contacts")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAdd = true
                } label: {
                    Label("Add Contact", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                AddRecoveryContactView()
            }
            .frame(minWidth: 420, minHeight: 400)
        }
    }

    private func deleteContacts(at offsets: IndexSet) {
        for index in offsets {
            context.delete(contacts[index])
        }
        try? PersistenceController.shared.save(context)
    }
}

private struct AddRecoveryContactView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context

    @State private var displayName = ""
    @State private var emailAddress = ""
    @State private var phoneNumber = ""
    @State private var relationship = ""
    @State private var notes = ""

    var body: some View {
        Form {
            Section("Contact") {
                TextField("Name", text: $displayName)
                TextField("Email", text: $emailAddress)
                TextField("Phone (optional)", text: $phoneNumber)
                TextField("Relationship", text: $relationship,
                          prompt: Text("Spouse, sibling, trusted friend…"))
            }

            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
                Text("Include instructions for how to reach you and any relevant context. These notes are stored in the encrypted archive backup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Add Recovery Contact")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || emailAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let contact = PersistenceController.shared.insertPrivate(
            RecoveryContactEntity.self,
            into: context
        )
        contact.displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.emailAddress = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.phoneNumber = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.relationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : notes.trimmingCharacters(in: .whitespacesAndNewlines)
        contact.createdAt = .now
        contact.updatedAt = .now

        try? PersistenceController.shared.save(context)
        dismiss()
    }
}

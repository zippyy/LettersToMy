import CoreData
import SwiftUI

struct FamilyView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChildProfile.createdAt, ascending: true)],
        animation: .default
    ) private var children: FetchedResults<ChildProfile>

    @State private var name = ""
    @State private var birthDate = Date.now
    @State private var hasBirthDate = false

    private var child: ChildProfile? { children.first }

    var body: some View {
        NavigationStack {
            Form {
                Section("Child") {
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
                }

                Section {
                    Button("Save Family Profile") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("The birth date is used only to calculate age-based letter unlocks and stays inside the private or explicitly shared family archive.")
                }
            }
            .navigationTitle("Family")
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let child else { return }
        name = child.name
        if let savedBirthDate = child.birthDate {
            birthDate = savedBirthDate
            hasBirthDate = true
        }
    }

    private func save() {
        let persistence = PersistenceController.shared
        let target: ChildProfile
        if let child {
            target = child
        } else {
            target = persistence.insertPrivate(ChildProfile.self, into: managedObjectContext)
        }

        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.birthDate = hasBirthDate ? birthDate : nil
        target.updatedAt = .now

        if target.partition == nil {
            let partition = persistence.insertPrivate(
                SharePartitionRecord.self,
                into: managedObjectContext
            )
            partition.kind = .recipientInbox
            partition.scopeID = target.id
            partition.displayName = "\(target.name)'s Recipient Inbox"
            target.partition = partition
        } else {
            target.partition?.displayName = "\(target.name)'s Recipient Inbox"
            target.partition?.updatedAt = .now
        }

        try? persistence.save(managedObjectContext)
    }
}

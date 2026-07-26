import SwiftData
import SwiftUI

struct FamilyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChildProfile.createdAt) private var children: [ChildProfile]

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
                        DatePicker("Birth date", selection: $birthDate, in: ...Date.now, displayedComponents: .date)
                    }
                }

                Section {
                    Button("Save Family Profile") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } footer: {
                    Text("The birth date is used only to calculate age-based letter unlocks and is stored in your private app data.")
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
        let target = child ?? ChildProfile()
        if child == nil {
            modelContext.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        target.birthDate = hasBirthDate ? birthDate : nil
        target.updatedAt = .now
        try? modelContext.save()
    }
}

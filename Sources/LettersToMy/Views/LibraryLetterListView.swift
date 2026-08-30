import CoreData
import SwiftUI

/// Compact-width destination for a single library category. The parent owns
/// the child filter so it remains consistent when navigating between categories.
struct LibraryLetterListView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Letter.updatedAt, ascending: false)],
        animation: .default
    ) private var letters: FetchedResults<Letter>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChildProfile.createdAt, ascending: true)],
        animation: .default
    ) private var children: FetchedResults<ChildProfile>

    let statusFilter: LetterStatus?
    @Binding var selectedChildID: UUID?
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var editingLetter: Letter?

    private var selectedChild: ChildProfile? {
        children.first { $0.id == selectedChildID }
    }

    private func child(for letter: Letter) -> ChildProfile? {
        if let selectedChild { return selectedChild }
        guard let childID = letter.childID else { return nil }
        return children.first { $0.id == childID }
    }

    private var filteredLetters: [Letter] {
        let snapshots = letters.map { letter in
            LibraryLetterSnapshot(
                id: letter.id,
                childID: letter.childID,
                title: letter.title,
                body: letter.body,
                authorName: letter.authorName,
                isDraft: letter.isDraft,
                status: letter.status(for: child(for: letter))
            )
        }
        let ids = Set(LetterLibraryFilter.filter(
            snapshots,
            status: statusFilter,
            childID: selectedChildID,
            searchText: searchText
        ).map(\.id))
        return letters.filter { ids.contains($0.id) }
    }

    var body: some View {
        Group {
            if filteredLetters.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Letters Yet" : "No Results",
                    systemImage: searchText.isEmpty ? "envelope.badge" : "magnifyingglass",
                    description: Text(searchText.isEmpty ? "Write the first letter for a future moment." : "Try a different search or filter.")
                )
            } else {
                List(filteredLetters) { letter in
                    NavigationLink {
                        LetterDetailView(letter: letter, child: child(for: letter)) {
                            editingLetter = letter
                            showingEditor = true
                        }
                    } label: {
                        LetterRow(letter: letter, child: child(for: letter))
                    }
                    .contextMenu {
                        if PersistenceController.shared.canUpdate(letter) {
                            Button("Edit") {
                                editingLetter = letter
                                showingEditor = true
                            }
                        }
                        if PersistenceController.shared.canDelete(letter) {
                            Button("Delete", role: .destructive) {
                                managedObjectContext.delete(letter)
                                try? PersistenceController.shared.save(managedObjectContext)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(statusFilter?.title ?? "All Letters")
        .searchable(text: $searchText, prompt: "Search letters")
        .toolbar {
            if children.count > 1 {
                ToolbarItem(placement: .navigation) {
                    Picker("Recipient", selection: $selectedChildID) {
                        Text("All Children").tag(nil as UUID?)
                        ForEach(children) { child in
                            Text(child.name.isEmpty ? "Unnamed" : child.name)
                                .tag(child.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingLetter = nil
                    showingEditor = true
                } label: {
                    Label("New Letter", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                LetterEditorView(letter: editingLetter, child: selectedChild)
            }
            .environment(\.managedObjectContext, managedObjectContext)
        }
    }
}

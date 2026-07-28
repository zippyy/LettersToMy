import CoreData
import SwiftUI

struct LibraryView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Letter.updatedAt, ascending: false)],
        animation: .default
    ) private var letters: FetchedResults<Letter>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChildProfile.createdAt, ascending: true)],
        animation: .default
    ) private var children: FetchedResults<ChildProfile>

    @State private var selection: Letter?
    @State private var statusFilter: LetterStatus?
    @State private var searchText = ""
    @State private var showingEditor = false
    @State private var editingLetter: Letter?
    @State private var selectedChildID: UUID?

    private var selectedChild: ChildProfile? {
        children.first { $0.id == selectedChildID } ?? children.first
    }

    private var filteredLetters: [Letter] {
        letters.filter { letter in
            let matchesChild = selectedChildID == nil || letter.childID == selectedChildID
            let matchesStatus = statusFilter == nil || letter.status(for: selectedChild) == statusFilter
            let matchesSearch = searchText.isEmpty
                || letter.title.localizedCaseInsensitiveContains(searchText)
                || letter.body.localizedCaseInsensitiveContains(searchText)
                || letter.authorName.localizedCaseInsensitiveContains(searchText)
            return matchesChild && matchesStatus && matchesSearch
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $statusFilter) {
                Label("All Letters", systemImage: "tray.full")
                    .tag(nil as LetterStatus?)

                Section("Status") {
                    ForEach(LetterStatus.allCases) { status in
                        Label(status.title, systemImage: status.systemImage)
                            .tag(status as LetterStatus?)
                    }
                }
            }
            .navigationTitle("Letters")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingLetter = nil
                        showingEditor = true
                    } label: {
                        Label("New Letter", systemImage: "square.and.pencil")
                    }
                }
            }
        } content: {
            Group {
                if filteredLetters.isEmpty {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No Letters Yet" : "No Results",
                            systemImage: searchText.isEmpty ? "envelope.badge" : "magnifyingglass",
                            description: Text(searchText.isEmpty ? "Write the first letter for a future moment." : "Try a different search or filter.")
                        )
                        Button {
                            editingLetter = nil
                            showingEditor = true
                        } label: {
                            Label("New Letter", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List(filteredLetters, selection: $selection) { letter in
                        LetterRow(letter: letter, child: selectedChild)
                            .tag(letter)
                            .contextMenu {
                                if PersistenceController.shared.canUpdate(letter) {
                                    Button("Edit") {
                                        editingLetter = letter
                                        showingEditor = true
                                    }
                                }
                                if PersistenceController.shared.canDelete(letter) {
                                    Button("Delete", role: .destructive) {
                                        delete(letter)
                                    }
                                }
                            }
                    }
                    .searchable(text: $searchText, prompt: "Search letters")
                }
            }
            .navigationTitle(statusFilter?.title ?? "All Letters")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingLetter = nil
                        showingEditor = true
                    } label: {
                        Label("New Letter", systemImage: "square.and.pencil")
                    }
                }
                if children.count > 1 {
                    ToolbarItem(placement: .navigation) {
                        childPicker
                    }
                }
            }
        } detail: {
            if let selection {
                LetterDetailView(letter: selection, child: selectedChild) {
                    editingLetter = selection
                    showingEditor = true
                }
            } else {
                ContentUnavailableView(
                    "Select a Letter",
                    systemImage: "envelope",
                    description: Text("Choose a letter to read its details.")
                )
            }
        }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                LetterEditorView(letter: editingLetter, child: selectedChild)
            }
            .environment(\.managedObjectContext, managedObjectContext)
            .frame(minWidth: 480, minHeight: 620)
        }
        .onAppear {
            if selectedChildID == nil { selectedChildID = children.first?.id }
        }
    }

    private var childPicker: some View {
        Picker("Recipient", selection: $selectedChildID) {
            Text("All Children").tag(nil as UUID?)
            ForEach(children) { child in
                Text(child.name.isEmpty ? "Unnamed" : child.name)
                    .tag(child.id as UUID?)
            }
        }
        .pickerStyle(.menu)
    }

    private func delete(_ letter: Letter) {
        guard PersistenceController.shared.canPerform(
            .deleteContent,
            context: letter.collaborationContext(for: selectedChild),
            target: letter
        ) else { return }

        if selection?.objectID == letter.objectID {
            selection = nil
        }
        managedObjectContext.delete(letter)
        try? PersistenceController.shared.save(managedObjectContext)
    }
}

private struct LetterRow: View {
    @ObservedObject var letter: Letter
    let child: ChildProfile?

    private var status: LetterStatus { letter.status(for: child) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.systemImage)
                .frame(width: 28, height: 28)
                .foregroundStyle(status == .unlocked ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(letter.title.isEmpty ? "Untitled Letter" : letter.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(letter.schedule.summary(birthDate: child?.birthDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if letter.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
            }
        }
        .padding(.vertical, 4)
    }
}

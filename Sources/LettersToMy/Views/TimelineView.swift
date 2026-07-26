import CoreData
import SwiftUI

struct TimelineView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Letter.createdAt, ascending: false)],
        animation: .default
    ) private var letters: FetchedResults<Letter>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ChildProfile.createdAt, ascending: true)],
        animation: .default
    ) private var children: FetchedResults<ChildProfile>

    @State private var selectedChildID: UUID?

    private var selectedChild: ChildProfile? {
        children.first { $0.id == selectedChildID } ?? children.first
    }

    private var scheduledLetters: [Letter] {
        letters
            .filter { letter in
                guard !letter.isDraft else { return false }
                if let childID = selectedChildID {
                    return letter.childID == childID
                }
                return true
            }
            .sorted {
                let lhs = $0.schedule.resolvedDate(birthDate: selectedChild?.birthDate) ?? .distantFuture
                let rhs = $1.schedule.resolvedDate(birthDate: selectedChild?.birthDate) ?? .distantFuture
                return lhs < rhs
            }
    }

    var body: some View {
        NavigationStack {
            Group {
                if scheduledLetters.isEmpty {
                    ContentUnavailableView(
                        "No Scheduled Letters",
                        systemImage: "calendar.badge.plus",
                        description: Text("Sealed letters will appear here in unlock order.")
                    )
                } else {
                    List(scheduledLetters) { letter in
                        HStack(spacing: 14) {
                            Image(systemName: letter.status(for: selectedChild).systemImage)
                                .font(.title2)
                                .frame(width: 34)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(letter.title.isEmpty ? "Untitled Letter" : letter.title)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(letter.schedule.summary(birthDate: selectedChild?.birthDate))
                                        .foregroundStyle(.secondary)
                                    if selectedChildID == nil, let childID = letter.childID,
                                       let child = children.first(where: { $0.id == childID }) {
                                        Text("· \(child.name)")
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Timeline")
            .toolbar {
                if children.count > 1 {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Recipient", selection: $selectedChildID) {
                            Text("All").tag(nil as UUID?)
                            ForEach(children) { child in
                                Text(child.name.isEmpty ? "Unnamed" : child.name)
                                    .tag(child.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            .onAppear {
                if selectedChildID == nil { selectedChildID = children.first?.id }
            }
        }
    }
}

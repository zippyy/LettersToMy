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

    private var child: ChildProfile? { children.first }

    private var scheduledLetters: [Letter] {
        letters
            .filter { !$0.isDraft }
            .sorted {
                let lhs = $0.schedule.resolvedDate(birthDate: child?.birthDate) ?? .distantFuture
                let rhs = $1.schedule.resolvedDate(birthDate: child?.birthDate) ?? .distantFuture
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
                            Image(systemName: letter.status(for: child).systemImage)
                                .font(.title2)
                                .frame(width: 34)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(letter.title.isEmpty ? "Untitled Letter" : letter.title)
                                    .font(.headline)
                                Text(letter.schedule.summary(birthDate: child?.birthDate))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Timeline")
        }
    }
}

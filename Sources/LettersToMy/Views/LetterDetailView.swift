import CoreData
import SwiftUI

struct LetterDetailView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @ObservedObject var letter: Letter
    @AppStorage("recipientPreview") private var recipientPreview = false

    let child: ChildProfile?
    let editAction: () -> Void

    private var attachments: [LetterAttachment] {
        (letter.attachments?.allObjects as? [LetterAttachment] ?? [])
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var isVisible: Bool {
        !recipientPreview || letter.isUnlocked(for: child)
    }

    private var canUpdate: Bool {
        PersistenceController.shared.canUpdate(letter)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                Divider()

                if isVisible {
                    Text(letter.body.isEmpty ? "No message has been written yet." : letter.body)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if !attachments.isEmpty {
                        attachmentSection
                    }
                } else {
                    lockedContent
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .navigationTitle(letter.title.isEmpty ? "Untitled Letter" : letter.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if canUpdate {
                    Button {
                        letter.isFavorite.toggle()
                        letter.updatedAt = .now
                        try? PersistenceController.shared.save(managedObjectContext)
                    } label: {
                        Label("Favorite", systemImage: letter.isFavorite ? "heart.fill" : "heart")
                    }

                    if !recipientPreview,
                       !letter.isDraft,
                       letter.unlockRuleKind == .lifeEvent,
                       letter.manuallyReleasedAt == nil {
                        Button("Release Now") {
                            letter.manuallyReleasedAt = .now
                            letter.updatedAt = .now
                            try? PersistenceController.shared.save(managedObjectContext)
                        }
                    }

                    Button("Edit", action: editAction)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(letter.title.isEmpty ? "Untitled Letter" : letter.title)
                .font(.largeTitle.bold())

            if !letter.authorName.isEmpty {
                Text("From \(letter.authorName)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Label(
                letter.schedule.summary(birthDate: child?.birthDate),
                systemImage: letter.status(for: child).systemImage
            )
            .font(.headline)
        }
    }

    private var lockedContent: some View {
        ContentUnavailableView {
            Label("This Letter Is Still Sealed", systemImage: "lock.fill")
        } description: {
            Text("It will be available \(letter.schedule.summary(birthDate: child?.birthDate).lowercased()).")
        }
        .frame(maxWidth: .infinity, minHeight: 280)
    }

    private var attachmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memories")
                .font(.title2.bold())

            ForEach(attachments) { attachment in
                Label(attachment.fileName, systemImage: attachment.kind.systemImage)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

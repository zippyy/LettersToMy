import AVKit
import CoreData
import SwiftUI

struct LetterDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @ObservedObject var letter: Letter
    @AppStorage("recipientPreview") private var recipientPreview = false

    let child: ChildProfile?
    let editAction: () -> Void

    @State private var pendingDeletion: Letter?
    @State private var deleteError: String?

    private var attachments: [LetterAttachment] {
        (letter.attachments?.allObjects as? [LetterAttachment] ?? [])
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var isVisible: Bool {
        if recipientPreview {
            return letter.isUnlocked(for: child)
        }
        // Preview disabled — seeing sealed bodies is a privilege, not a
        // side effect of the global toggle. Non-owners still see locked
        // content even when the toggle is off.
        return PersistenceController.shared.canPerform(
            .viewSealedContent,
            context: letter.collaborationContext(for: child),
            target: letter
        )
    }

    private var canUpdate: Bool {
        PersistenceController.shared.canUpdate(letter)
    }

    private var canDelete: Bool {
        PersistenceController.shared.canDelete(letter)
            && PersistenceController.shared.canPerform(
                .deleteContent,
                context: letter.collaborationContext(for: child),
                target: letter
            )
    }

    private var canRelease: Bool {
        PersistenceController.shared.canPerform(
            .releaseLifeEventLetter,
            context: letter.collaborationContext(for: child),
            target: letter
        )
    }

    var body: some View {
        // Defensive guard for the compact-navigation delete path: the delete
        // save happens before the NavigationStack finishes dismissing, so the
        // detail view can be asked to render one more time against a deleted
        // object. Accessing any faulted property of a deleted object would
        // throw "Object has been deleted or invalidated", so bail out early
        // with an inert placeholder and let the stack pop.
        if letter.isDeleted {
            return AnyView(EmptyView())
        }
        return AnyView(detailContent)
    }

    private var detailContent: some View {
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
                       letter.manuallyReleasedAt == nil,
                       canRelease {
                        Button("Release Now") {
                            letter.manuallyReleasedAt = .now
                            letter.updatedAt = .now
                            try? PersistenceController.shared.save(managedObjectContext)
                        }
                    }

                    Button("Edit", action: editAction)
                }

                if canDelete {
                    Button(role: .destructive) {
                        pendingDeletion = letter
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .letterDeletion(
            pendingLetter: $pendingDeletion,
            errorMessage: $deleteError,
            child: { _ in child },
            context: managedObjectContext,
            dismissAction: dismiss
        )
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
                VStack(alignment: .leading, spacing: 0) {
                    if attachment.kind == .photo,
                       let data = attachment.data,
                       let image = PlatformImage(data: data) {
                        #if os(iOS)
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        #else
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        #endif
                    } else if attachment.kind == .video,
                              let data = attachment.data {
                        #if os(iOS)
                        let player = videoPlayer(for: data)
                        if (player.currentItem?.asset as? AVURLAsset)?.url != nil {
                            VideoPlayer(player: player)
                                .frame(minHeight: 200)
                        } else {
                            Label(attachment.fileName, systemImage: "play.rectangle")
                                .padding()
                        }
                        #endif
                    }
                    HStack {
                        Label(attachment.fileName, systemImage: attachment.kind.systemImage)
                            .padding(12)
                        Spacer()
                        if canUpdate {
                            Button(role: .destructive) {
                                deleteAttachment(attachment)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .padding(.trailing, 8)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func deleteAttachment(_ attachment: LetterAttachment) {
        attachment.letter = nil
        managedObjectContext.delete(attachment)
        try? PersistenceController.shared.save(managedObjectContext)
    }

    private func videoPlayer(for data: Data) -> AVPlayer {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).mov")
        try? data.write(to: url)
        return AVPlayer(url: url)
    }
}

#if os(iOS)
private typealias PlatformImage = UIImage
#else
private typealias PlatformImage = NSImage
#endif

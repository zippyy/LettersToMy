import LettersToMyCore
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LetterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FamilyBranchRecord.createdAt) private var branches: [FamilyBranchRecord]
    @Query(sort: \ArchiveFolderRecord.createdAt) private var folders: [ArchiveFolderRecord]

    let letter: Letter?
    let child: ChildProfile?

    @State private var title: String
    @State private var bodyText: String
    @State private var authorName: String
    @State private var branchID: UUID?
    @State private var folderID: UUID?
    @State private var unlockKind: UnlockRuleKind
    @State private var unlockDate: Date
    @State private var unlockAgeYears: Int
    @State private var lifeEventName: String
    @State private var showingFileImporter = false
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var importError: String?

    init(letter: Letter?, child: ChildProfile?) {
        self.letter = letter
        self.child = child
        _title = State(initialValue: letter?.title ?? "")
        _bodyText = State(initialValue: letter?.body ?? "")
        _authorName = State(initialValue: letter?.authorName ?? "")
        _branchID = State(initialValue: letter?.branchID)
        _folderID = State(initialValue: letter?.folderID)
        _unlockKind = State(initialValue: letter?.unlockRuleKind ?? .specificDate)
        _unlockDate = State(initialValue: letter?.unlockDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now)
        _unlockAgeYears = State(initialValue: letter?.unlockAgeYears ?? 5)
        _lifeEventName = State(initialValue: letter?.lifeEventName ?? "")
    }

    private var availableFolders: [ArchiveFolderRecord] {
        guard let branchID else { return [] }
        return folders.filter { $0.branchID == branchID }
    }

    var body: some View {
        Form {
            Section("Letter") {
                TextField("Title", text: $title)
                TextField("From", text: $authorName)

                TextEditor(text: $bodyText)
                    .frame(minHeight: 220)
                    .accessibilityLabel("Letter message")
            }

            Section("Family side and folder") {
                Picker("Family side", selection: $branchID) {
                    Text("Unassigned").tag(nil as UUID?)
                    ForEach(branches) { branch in
                        Text(branch.name).tag(branch.id as UUID?)
                    }
                }
                .onChange(of: branchID) { _, newBranchID in
                    guard let folderID else { return }
                    if !folders.contains(where: { $0.id == folderID && $0.branchID == newBranchID }) {
                        self.folderID = nil
                    }
                }

                Picker("Folder", selection: $folderID) {
                    Text("No folder").tag(nil as UUID?)
                    ForEach(availableFolders) { folder in
                        Text(folder.name).tag(folder.id as UUID?)
                    }
                }
                .disabled(branchID == nil)

                Text("Family sides and folders determine which collaborators can work with this letter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Unlock") {
                Picker("Unlock rule", selection: $unlockKind) {
                    ForEach(UnlockRuleKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }

                switch unlockKind {
                case .specificDate:
                    DatePicker("Unlock date", selection: $unlockDate, in: Date.now..., displayedComponents: .date)
                case .birthdayAge:
                    Stepper("Age \(unlockAgeYears)", value: $unlockAgeYears, in: 1...100)
                    if child?.birthDate == nil {
                        Label("Add a birth date in Family before sealing this letter.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                case .lifeEvent:
                    TextField("Example: Wedding day", text: $lifeEventName)
                    Text("Life-event letters stay sealed until a parent releases them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Photos, video, and audio") {
                Button {
                    showingFileImporter = true
                } label: {
                    Label("Add Attachments", systemImage: "paperclip")
                }

                ForEach(pendingAttachments) { attachment in
                    Label(attachment.fileName, systemImage: attachment.kind.systemImage)
                }
            }
        }
        .navigationTitle(letter == nil ? "New Letter" : "Edit Letter")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                if letter?.isDraft == false {
                    Button("Save Changes") { save(sealed: true) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Save Draft") { save(sealed: false) }
                    Button("Seal Letter") { save(sealed: true) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSeal)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.image, .movie, .audio],
            allowsMultipleSelection: true,
            onCompletion: importFiles
        )
        .alert("Could Not Add Attachment", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
    }

    private var canSeal: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        switch unlockKind {
        case .specificDate:
            return unlockDate >= Calendar.current.startOfDay(for: .now)
        case .birthdayAge:
            return child?.birthDate != nil
        case .lifeEvent:
            return !lifeEventName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save(sealed: Bool) {
        let target = letter ?? Letter(childID: child?.id)
        if letter == nil {
            modelContext.insert(target)
        }

        target.childID = child?.id
        target.branchID = branchID
        target.folderID = folderID
        target.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        target.body = bodyText
        target.authorName = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        target.unlockRuleKind = unlockKind
        target.unlockDate = unlockKind == .specificDate ? unlockDate : nil
        target.unlockAgeYears = unlockKind == .birthdayAge ? unlockAgeYears : nil
        target.lifeEventName = unlockKind == .lifeEvent ? lifeEventName.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        target.updatedAt = .now
        target.sealedAt = sealed ? (target.sealedAt ?? .now) : nil

        for attachment in pendingAttachments {
            modelContext.insert(LetterAttachment(
                letterID: target.id,
                fileName: attachment.fileName,
                contentTypeIdentifier: attachment.contentTypeIdentifier,
                kind: attachment.kind,
                data: attachment.data
            ))
        }

        try? modelContext.save()
        dismiss()
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            for url in try result.get() {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }

                let values = try url.resourceValues(forKeys: [.contentTypeKey])
                let contentType = values.contentType ?? .data
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                pendingAttachments.append(PendingAttachment(
                    fileName: url.lastPathComponent,
                    contentTypeIdentifier: contentType.identifier,
                    kind: AttachmentKind(contentType: contentType),
                    data: data
                ))
            }
        } catch {
            importError = error.localizedDescription
        }
    }
}

private struct PendingAttachment: Identifiable {
    let id = UUID()
    let fileName: String
    let contentTypeIdentifier: String
    let kind: AttachmentKind
    let data: Data
}

private extension AttachmentKind {
    init(contentType: UTType) {
        if contentType.conforms(to: .image) {
            self = .photo
        } else if contentType.conforms(to: .movie) {
            self = .video
        } else if contentType.conforms(to: .audio) {
            self = .audio
        } else {
            self = .file
        }
    }
}

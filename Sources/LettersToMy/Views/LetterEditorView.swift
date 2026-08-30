import AVFoundation
import CoreData
import LettersToMyCore
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct LetterEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FamilyBranchRecord.createdAt, ascending: true)],
        animation: .default
    ) private var allBranches: FetchedResults<FamilyBranchRecord>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ArchiveFolderRecord.createdAt, ascending: true)],
        animation: .default
    ) private var allFolders: FetchedResults<ArchiveFolderRecord>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \SharePartitionRecord.createdAt, ascending: true)],
        animation: .default
    ) private var allPartitions: FetchedResults<SharePartitionRecord>

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
    @State private var showingCamera = false
    @State private var showingVoiceRecorder = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var pendingAttachments: [PendingAttachment] = []
    @State private var attachmentsToDelete = Set<NSManagedObjectID>()
    @State private var importError: String?
    @State private var saveError: String?
    @State private var selectedMilestone: MilestoneTemplate?
    @State private var permissionDenied = false

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

    private var targetStore: NSPersistentStore? {
        letter?.objectID.persistentStore ?? PersistenceController.shared.privateStore
    }

    private var branches: [FamilyBranchRecord] {
        allBranches.filter { $0.objectID.persistentStore === targetStore }
    }

    private var folders: [ArchiveFolderRecord] {
        allFolders.filter { $0.objectID.persistentStore === targetStore }
    }

    private var partitions: [SharePartitionRecord] {
        allPartitions.filter { $0.objectID.persistentStore === targetStore }
    }

    private var availableFolders: [ArchiveFolderRecord] {
        guard let branchID else { return [] }
        return folders.filter { $0.branchID == branchID }
    }

    @ViewBuilder
    private var unlockControls: some View {
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

    var body: some View {
        Form {
            if letter == nil {
                Section("Quick Start") {
                    Picker("Milestone", selection: $selectedMilestone) {
                        Text("Start from scratch").tag(nil as MilestoneTemplate?)
                        ForEach(MilestoneTemplate.all) { milestone in
                            Text(milestone.title).tag(milestone as MilestoneTemplate?)
                        }
                    }
                    .onChange(of: selectedMilestone) { _, milestone in
                        if let milestone { applyMilestone(milestone) }
                    }
                }
            }

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
                    clearFolderIfNeeded(for: newBranchID)
                }

                Picker("Folder", selection: $folderID) {
                    Text("No folder").tag(nil as UUID?)
                    ForEach(availableFolders) { folder in
                        Text(folder.name).tag(folder.id as UUID?)
                    }
                }
                .disabled(branchID == nil)

                Text("Family sides and folders determine the CloudKit share that contains this letter and which collaborators can receive it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Unlock") {
                Picker("Unlock rule", selection: $unlockKind) {
                    ForEach(UnlockRuleKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }

                unlockControls
            }

            Section("Photos, video, and audio") {
                Menu {
                    #if os(iOS)
                    Button {
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                    }
                    Button {
                        showingVoiceRecorder = true
                    } label: {
                        Label("Record Voice", systemImage: "mic")
                    }
                    #endif
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("Files", systemImage: "folder")
                    }
                } label: {
                    Label("Add Attachments", systemImage: "paperclip")
                }

                ForEach(pendingAttachments) { attachment in
                    Label(attachment.fileName, systemImage: attachment.kind.systemImage)
                }

                if !existingAttachments.isEmpty {
                    ForEach(existingAttachments) { attachment in
                        HStack {
                            Label(
                                attachment.fileName.isEmpty ? "Attachment" : attachment.fileName,
                                systemImage: attachment.kind.systemImage
                            )
                            .foregroundStyle(attachmentsToDelete.contains(attachment.objectID) ? .secondary : .primary)
                            Spacer()
                            Button {
                                if attachmentsToDelete.contains(attachment.objectID) {
                                    attachmentsToDelete.remove(attachment.objectID)
                                } else {
                                    attachmentsToDelete.insert(attachment.objectID)
                                }
                            } label: {
                                Image(systemName: attachmentsToDelete.contains(attachment.objectID) ? "arrow.uturn.backward" : "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
        .photosPicker(
            isPresented: $showingPhotoPicker,
            selection: $selectedPhotoItems,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            Task { await importPhotoItems(items) }
        }
        #if os(iOS)
        .sheet(isPresented: $showingCamera) {
            CameraPicker { attachment in
                if let attachment {
                    pendingAttachments.append(attachment)
                }
            }
        }
        .sheet(isPresented: $showingVoiceRecorder) {
            VoiceRecorderView { url in
                if let url, let data = try? Data(contentsOf: url) {
                    pendingAttachments.append(PendingAttachment(
                        fileName: "Voice Memo.m4a",
                        contentTypeIdentifier: "public.mpeg-4-audio",
                        kind: .audio,
                        data: data
                    ))
                }
            }
        }
        #endif
        .alert("Could Not Add Attachment", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "Unknown error")
        }
        .alert(
            "Permission Denied",
            isPresented: $permissionDenied
        ) {
            Button("OK") {}
        } message: {
            Text("Your role does not allow creating or editing a letter in the selected family side or folder.")
        }
        .alert(
            "Could Not Save Letter",
            isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveError ?? "The letter could not be saved. Your changes are still in the editor.")
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

    private var existingAttachments: [LetterAttachment] {
        Array((letter?.attachments as? Set<LetterAttachment>) ?? [])
    }

    private func save(sealed: Bool) {
        let persistence = PersistenceController.shared
        let isNew = letter == nil

        // Permission check before mutating the store.
        let collabContext = CollaborationContext(
            branchID: branchID,
            folderID: folderID,
            recipientID: child?.id,
            authorMemberID: letter?.authorMemberID
        )
        guard persistence.canPerform(
            isNew ? .createContent : .editContent,
            context: collabContext,
            target: letter
        ) else {
            // A denied permission must not look like a successful save.
            permissionDenied = true
            return
        }

        let target: Letter
        let targetPartition = selectedPartition(using: persistence)
        if let letter {
            target = letter
        } else {
            // Create the new letter in the SAME store as its destination
            // partition. A cross-store relationship to a shared partition
            // would crash the save, and a private-store letter would be
            // invisible to the archive owner when a collaborator creates it.
            if let partition = targetPartition {
                target = persistence.insert(
                    Letter.self,
                    inSameStoreAs: partition,
                    into: managedObjectContext
                )
            } else {
                target = persistence.insertPrivate(Letter.self, into: managedObjectContext)
            }
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
        if let partition = targetPartition {
            // Only assign the partition when it is in the same store as the
            // letter; cross-store relationships are invalid in Core Data.
            if partition.objectID.persistentStore === target.objectID.persistentStore {
                target.partition = partition
            }
        } else if isNew {
            let partition = persistence.insertPrivate(
                SharePartitionRecord.self,
                into: managedObjectContext
            )
            partition.kind = .archiveAdministration
            partition.displayName = "Family Archive Administration"
            target.partition = partition
        }

        // Delete attachments marked for removal.
        for objectID in attachmentsToDelete {
            if let existing = try? managedObjectContext.existingObject(with: objectID) {
                managedObjectContext.delete(existing)
            }
        }

        for pending in pendingAttachments {
            let attachment = persistence.insert(
                LetterAttachment.self,
                inSameStoreAs: target,
                into: managedObjectContext
            )
            attachment.letterID = target.id
            attachment.fileName = pending.fileName
            attachment.contentTypeIdentifier = pending.contentTypeIdentifier
            attachment.kind = pending.kind
            attachment.data = pending.data
            attachment.letter = target
        }

        switch saveLetter({ try persistence.save(managedObjectContext) }) {
        case .saved:
            break
        case .failed(let message):
            saveError = message
            return
        }

        if isNew {
            let hasAttachments = !pendingAttachments.isEmpty || (letter?.attachments?.count ?? 0) > 0
            AppAnalytics.letterCreated(sealed: sealed, hasAttachments: hasAttachments)
        } else {
            AppAnalytics.letterEdited()
        }

        dismiss()
    }

    private func selectedPartition(using persistence: PersistenceController) -> SharePartitionRecord? {
        if let folderID,
           let folder = folders.first(where: { $0.id == folderID }),
           let partition = folder.partition {
            return partition
        }
        if let branchID,
           let branch = branches.first(where: { $0.id == branchID }),
           let partition = branch.partition {
            return partition
        }
        if let archive = partitions.first(where: { $0.kind == .archiveAdministration }) {
            return archive
        }

        // No partition exists yet — create a fresh admin partition in the
        // private store. The letter is created in the same store below, so
        // the relationship stays valid.
        let partition = persistence.insertPrivate(
            SharePartitionRecord.self,
            into: managedObjectContext
        )
        partition.kind = .archiveAdministration
        partition.displayName = "Family Archive Administration"
        return partition
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

    private func applyMilestone(_ milestone: MilestoneTemplate) {
        title = milestone.title
        bodyText = milestone.body
        unlockKind = milestone.unlockKind
        if milestone.unlockKind == .birthdayAge {
            unlockAgeYears = milestone.unlockAge ?? 5
        } else if milestone.unlockKind == .lifeEvent {
            lifeEventName = milestone.lifeEventName ?? ""
        }
        selectedMilestone = nil
    }

    private func clearFolderIfNeeded(for branchID: UUID?) {
        guard let folderID else { return }
        if !folders.contains(where: { $0.id == folderID && $0.branchID == branchID }) {
            self.folderID = nil
        }
    }

    private func importPhotoItems(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let contentType = item.supportedContentTypes.first ?? .jpeg
            pendingAttachments.append(PendingAttachment(
                fileName: "Photo",
                contentTypeIdentifier: contentType.identifier,
                kind: AttachmentKind(contentType: contentType),
                data: data
            ))
        }
    }
}

#if os(iOS)
private struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (PendingAttachment?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (PendingAttachment?) -> Void
        let dismiss: DismissAction

        init(onCapture: @escaping (PendingAttachment?) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let videoURL = info[.mediaURL] as? URL,
               let data = try? Data(contentsOf: videoURL) {
                onCapture(PendingAttachment(
                    fileName: "Video \(Date.now.formatted(date: .omitted, time: .shortened)).mov",
                    contentTypeIdentifier: "public.mpeg-4",
                    kind: .video,
                    data: data
                ))
            } else if let image = info[.originalImage] as? UIImage,
                      let data = image.jpegData(compressionQuality: 0.9) {
                onCapture(PendingAttachment(
                    fileName: "Photo \(Date.now.formatted(date: .omitted, time: .shortened)).jpg",
                    contentTypeIdentifier: "public.jpeg",
                    kind: .photo,
                    data: data
                ))
            } else {
                onCapture(nil)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
            dismiss()
        }
    }
}
#endif

// MARK: - Voice Recorder (iOS only)

#if os(iOS)
private struct VoiceRecorderView: View {
    @Environment(\.dismiss) private var dismiss
    let onFinish: (URL?) -> Void

    @State private var recorder: AVAudioRecorder?
    @State private var isRecording = false
    @State private var recordingURL: URL?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if isRecording {
                Text("Recording…")
                    .font(.title2)
                    .foregroundStyle(.red)
                Button {
                    stopRecording()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.red)
                }
                .labelStyle(.iconOnly)
            } else if recordingURL != nil {
                Text("Recording saved")
                    .font(.title2)
                Button {
                    onFinish(recordingURL)
                    dismiss()
                } label: {
                    Label("Attach Recording", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    startRecording()
                } label: {
                    Label("Record", systemImage: "mic.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.blue)
                }
                .labelStyle(.iconOnly)
            }

            Spacer()

            Button("Cancel") {
                recorder?.stop()
                dismiss()
            }
        }
        .padding()
        .onDisappear {
            recorder?.stop()
        }
    }

    private func startRecording() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)

        recorder = try? AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        isRecording = true
    }

    private func stopRecording() {
        recorder?.stop()
        isRecording = false
    }
}
#endif

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

// MARK: - Milestone Templates

struct MilestoneTemplate: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let body: String
    let unlockKind: UnlockRuleKind
    let unlockAge: Int?
    let lifeEventName: String?

    static let all: [MilestoneTemplate] = [
        MilestoneTemplate(
            title: "Your First Birthday",
            body: "Dear little one,\n\nHappy first birthday! You've grown so much this year…\n\n",
            unlockKind: .birthdayAge,
            unlockAge: 1,
            lifeEventName: nil
        ),
        MilestoneTemplate(
            title: "Starting School",
            body: "Today you start school. I remember when…\n\n",
            unlockKind: .birthdayAge,
            unlockAge: 5,
            lifeEventName: nil
        ),
        MilestoneTemplate(
            title: "Your 10th Birthday",
            body: "Double digits! You're growing up so fast…\n\n",
            unlockKind: .birthdayAge,
            unlockAge: 10,
            lifeEventName: nil
        ),
        MilestoneTemplate(
            title: "Sweet Sixteen",
            body: "Sixteen years old. I am so proud of the person you're becoming…\n\n",
            unlockKind: .birthdayAge,
            unlockAge: 16,
            lifeEventName: nil
        ),
        MilestoneTemplate(
            title: "Graduation Day",
            body: "Today you graduate. All those years of hard work…\n\n",
            unlockKind: .lifeEvent,
            unlockAge: nil,
            lifeEventName: "Graduation"
        ),
        MilestoneTemplate(
            title: "Your Wedding Day",
            body: "On this beautiful day, as you start this new chapter…\n\n",
            unlockKind: .lifeEvent,
            unlockAge: nil,
            lifeEventName: "Wedding"
        ),
        MilestoneTemplate(
            title: "Becoming a Parent",
            body: "Now you understand. The moment you held your own child…\n\n",
            unlockKind: .lifeEvent,
            unlockAge: nil,
            lifeEventName: "Becoming a parent"
        ),
        MilestoneTemplate(
            title: "A Letter for When You Need It",
            body: "If you're reading this, you might be having a hard day…\n\n",
            unlockKind: .lifeEvent,
            unlockAge: nil,
            lifeEventName: "Encouragement"
        ),
    ]
}

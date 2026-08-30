import CoreData
import Foundation
import Testing
@testable import LettersToMy

/// Core Data behavior tests for letter deletion: cascade of attachments,
/// deletion across draft/sealed/unlocked states, private and shared stores,
/// selection-state cleanup, and the save-failure path.
///
/// These tests construct a real in-memory `PersistenceController` and drive
/// the same `LetterDeletion.perform` flow the UI uses, so they pin the actual
/// persistence behavior rather than mocked relationships.
@Suite(.serialized)
@MainActor
struct LetterDeletionCoreDataTests {
    /// A controller whose private store is in-memory (CloudKit unavailable in
    /// the test host, so no shared store is created).
    private func makeController() async -> PersistenceController {
        let controller = PersistenceController(inMemory: true)
        await controller.loadStores()
        return controller
    }

    private func fetchLetters(_ context: NSManagedObjectContext) -> [Letter] {
        let request = NSFetchRequest<Letter>(entityName: "Letter")
        return (try? context.fetch(request)) ?? []
    }

    private func fetchAttachments(_ context: NSManagedObjectContext) -> [LetterAttachment] {
        let request = NSFetchRequest<LetterAttachment>(entityName: "LetterAttachment")
        return (try? context.fetch(request)) ?? []
    }

    private func makeDraft(in controller: PersistenceController, context: NSManagedObjectContext) -> Letter {
        let letter = controller.insertPrivate(Letter.self, into: context)
        letter.title = "Draft Letter"
        letter.body = "body"
        letter.sealedAt = nil
        return letter
    }

    private func makeSealed(in controller: PersistenceController, context: NSManagedObjectContext) -> Letter {
        let letter = controller.insertPrivate(Letter.self, into: context)
        letter.title = "Sealed Letter"
        letter.body = "body"
        letter.sealedAt = .now
        letter.unlockRuleKind = .specificDate
        letter.unlockDate = Calendar.current.date(byAdding: .year, value: 10, to: .now)
        return letter
    }

    private func makeUnlocked(in controller: PersistenceController, context: NSManagedObjectContext) -> Letter {
        let letter = controller.insertPrivate(Letter.self, into: context)
        letter.title = "Unlocked Letter"
        letter.body = "body"
        letter.sealedAt = .now
        letter.unlockRuleKind = .specificDate
        letter.unlockDate = Calendar.current.date(byAdding: .day, value: -1, to: .now)
        return letter
    }

    @discardableResult
    private func addAttachment(to letter: Letter, in controller: PersistenceController, context: NSManagedObjectContext) -> LetterAttachment {
        let attachment = controller.insert(LetterAttachment.self, inSameStoreAs: letter, into: context)
        attachment.letterID = letter.id
        attachment.fileName = "photo.jpg"
        attachment.kind = .photo
        attachment.data = Data(repeating: 0xAB, count: 2048)
        attachment.letter = letter
        return attachment
    }

    @Test func deletingDraftRemovesLetter() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let draft = makeDraft(in: controller, context: context)
        try? controller.save(context)

        let outcome = LetterDeletion.perform(draft, in: context, child: nil, persistence: controller)

        #expect(outcome == .deleted)
        #expect(fetchLetters(context).isEmpty)
    }

    @Test func deletingSealedRemovesLetter() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let sealed = makeSealed(in: controller, context: context)
        try? controller.save(context)

        let outcome = LetterDeletion.perform(sealed, in: context, child: nil, persistence: controller)

        #expect(outcome == .deleted)
        #expect(fetchLetters(context).isEmpty)
    }

    @Test func deletingUnlockedRemovesLetter() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let unlocked = makeUnlocked(in: controller, context: context)
        try? controller.save(context)

        let outcome = LetterDeletion.perform(unlocked, in: context, child: nil, persistence: controller)

        #expect(outcome == .deleted)
        #expect(fetchLetters(context).isEmpty)
    }

    @Test func deletingLetterCascadesAttachments() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let letter = makeSealed(in: controller, context: context)
        addAttachment(to: letter, in: controller, context: context)
        addAttachment(to: letter, in: controller, context: context)
        try? controller.save(context)

        #expect(fetchAttachments(context).count == 2)

        let outcome = LetterDeletion.perform(letter, in: context, child: nil, persistence: controller)

        #expect(outcome == .deleted)
        #expect(fetchLetters(context).isEmpty)
        // Cascade must leave no orphaned attachment records or data behind.
        #expect(fetchAttachments(context).isEmpty)
    }

    @Test func deletingOneLetterLeavesOthersIntact() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let target = makeSealed(in: controller, context: context)
        let other = makeDraft(in: controller, context: context)
        addAttachment(to: target, in: controller, context: context)
        try? controller.save(context)

        _ = LetterDeletion.perform(target, in: context, child: nil, persistence: controller)

        let remaining = fetchLetters(context)
        #expect(remaining.count == 1)
        #expect(remaining.first?.objectID == other.objectID)
    }

    @Test func saveFailureRollsBackDeletionAndReportsFailure() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let draft = makeDraft(in: controller, context: context)
        try? controller.save(context)

        struct SaveError: Error {}
        let failingSave: (NSManagedObjectContext) throws -> Void = { _ in throw SaveError() }

        let outcome = LetterDeletion.perform(
            draft,
            in: context,
            child: nil,
            persistence: controller,
            save: failingSave
        )

        // .failed carries an associated message; match the case directly.
        guard case .failed = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        // The letter must still exist — the failed save must not look like a
        // successful deletion.
        #expect(fetchLetters(context).count == 1)
    }

    @Test func unrelatedPendingEditsSurviveFailedDelete() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let draft = makeDraft(in: controller, context: context)
        let other = makeDraft(in: controller, context: context)
        try? controller.save(context)

        // Simulate an unrelated unsaved edit in the same context.
        other.title = "Edited Title"

        struct SaveError: Error {}
        let failingSave: (NSManagedObjectContext) throws -> Void = { _ in throw SaveError() }

        let outcome = LetterDeletion.perform(
            draft,
            in: context,
            child: nil,
            persistence: controller,
            save: failingSave
        )

        guard case .failed = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        // The draft survives and the unrelated edit is preserved (selective
        // rollback via undo group, not a blanket rollback).
        #expect(fetchLetters(context).count == 2)
        let otherNow = fetchLetters(context).first { $0.objectID == other.objectID }
        #expect(otherNow?.title == "Edited Title")
    }

    @Test func deletingLetterInPrivateStoreWorks() async {
        let controller = await makeController()
        let context = controller.container.viewContext
        let letter = makeSealed(in: controller, context: context)
        try? controller.save(context)

        #expect(letter.objectID.persistentStore === controller.privateStore)

        let outcome = LetterDeletion.perform(letter, in: context, child: nil, persistence: controller)
        #expect(outcome == .deleted)
        #expect(fetchLetters(context).isEmpty)
    }

    @Test func deletingLetterInSharedStoreWorks() async {
        let controller = await makeController()
        let context = controller.container.viewContext

        // Build a second in-memory store to stand in for the shared store.
        // A normal Core Data delete in a context must work regardless of
        // which store the object belongs to.
        let sharedDescription = NSPersistentStoreDescription()
        sharedDescription.type = NSInMemoryStoreType
        sharedDescription.configuration = PersistenceController.sharedConfigurationName
        controller.container.persistentStoreCoordinator.addPersistentStore(with: sharedDescription) { _, error in
            #expect(error == nil)
        }
        guard let sharedStore = controller.container.persistentStoreCoordinator.persistentStores.last else {
            Issue.record("Expected a shared in-memory store")
            return
        }

        let letter = NSEntityDescription.insertNewObject(
            forEntityName: "Letter",
            into: context
        ) as! Letter
        letter.title = "Shared Letter"
        letter.body = "body"
        letter.sealedAt = .now
        context.assign(letter, to: sharedStore)
        try? controller.save(context)

        #expect(letter.objectID.persistentStore === sharedStore)

        let outcome = LetterDeletion.perform(letter, in: context, child: nil, persistence: controller)
        #expect(outcome == .deleted)
        #expect(fetchLetters(context).isEmpty)
    }
}

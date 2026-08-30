import CoreData
import Foundation
import SwiftUI

/// Confirmation copy for deleting a letter, keyed off its current state so a
/// draft, a sealed/scheduled letter, and an unlocked letter each get accurate
/// wording. Used by every deletion surface (list swipe, context menu, detail
/// toolbar) so the user always sees the same framing.
enum LetterDeletionCopy {
    static func title(for letter: Letter, child: ChildProfile?) -> String {
        if letter.isDraft { return "Delete Draft?" }
        return letter.isUnlocked(for: child) ? "Delete Letter?" : "Delete Sealed Letter?"
    }

    static func buttonTitle(for letter: Letter, child: ChildProfile?) -> String {
        if letter.isDraft { return "Delete Draft" }
        return letter.isUnlocked(for: child) ? "Delete Letter" : "Delete Sealed Letter"
    }

    static func message(for letter: Letter, child: ChildProfile?) -> String {
        if letter.isDraft {
            return "This permanently removes the draft and its attachments."
        }
        return "This permanently removes this letter and its attachments."
    }
}

/// The single deletion flow for Letters.
///
/// Every surface (split library, compact library list, letter detail) funnels
/// through here so permission gating, save-failure handling, and error
/// surfacing stay identical. Highlights:
///   - Permission gate reuses the existing collaboration system
///     (`canPerform(.deleteContent, ...)`); it never bypasses owner/member
///     roles, branch/folder scope, or shared-store permissions.
///   - The delete is wrapped in an undo group so a failed save can revert
///     ONLY the deletion — unrelated unsaved edits in the same context are
///     preserved (a blanket `rollback()` would discard them).
///   - A failed save never reports success: it returns `.failed`, logs the
///     detailed error, and surfaces a clean user-facing message.
enum LetterDeletion {
    enum Outcome: Equatable {
        case deleted
        case denied
        case failed(String)
    }

    @MainActor
    @discardableResult
    static func perform(
        _ letter: Letter,
        in context: NSManagedObjectContext,
        child: ChildProfile?,
        persistence: PersistenceController = .shared,
        save: ((NSManagedObjectContext) throws -> Void)? = nil
    ) -> Outcome {
        guard persistence.canPerform(
            .deleteContent,
            context: letter.collaborationContext(for: child),
            target: letter
        ) else {
            return .denied
        }

        // Group the deletion so a failed save can be undone without touching
        // unrelated pending edits in the same context.
        context.undoManager = context.undoManager ?? UndoManager()
        context.undoManager?.beginUndoGrouping()
        context.delete(letter)
        context.undoManager?.endUndoGrouping()

        let performSave = save ?? { try persistence.save($0) }
        do {
            try performSave(context)
            return .deleted
        } catch {
            context.undoManager?.undo()
            NSLog("LettersToMy: letter deletion save failed; delete rolled back: \(error)")
            return .failed(Self.userFacingMessage(for: error))
        }
    }

    /// A safe user-facing message — never a raw Core Data NSError dump.
    /// Full diagnostics are logged separately at the call site.
    static func userFacingMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSValidationRelationshipDeniedDeleteError {
            return "The letter could not be deleted because it is linked to a store that cannot be modified right now."
        }
        return "The letter could not be deleted. Please try again."
    }
}

/// Attaches the delete confirmation dialog and failure alert for a letter.
/// Set `pendingLetter` to trigger the flow; the dialog copy is derived from
/// the letter's state (draft / sealed / unlocked).
private struct LetterDeletionModifier: ViewModifier {
    @Binding var pendingLetter: Letter?
    @Binding var errorMessage: String?
    let child: (Letter) -> ChildProfile?
    let context: NSManagedObjectContext
    var selection: Binding<Letter?>?
    var dismissAction: DismissAction?
    var onDeleted: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                copyTitle,
                isPresented: presented,
                titleVisibility: .visible
            ) {
                Button(copyButtonTitle, role: .destructive) { confirm() }
                Button("Cancel", role: .cancel) { pendingLetter = nil }
            } message: {
                Text(copyMessage)
            }
            .alert("Could Not Delete Letter", isPresented: errorPresented) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "The letter could not be deleted.")
            }
    }

    private var presented: Binding<Bool> {
        Binding(
            get: { pendingLetter != nil },
            set: { if !$0 { pendingLetter = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private var copyTitle: String {
        guard let letter = pendingLetter else { return "Delete Letter?" }
        return LetterDeletionCopy.title(for: letter, child: child(letter))
    }

    private var copyButtonTitle: String {
        guard let letter = pendingLetter else { return "Delete Letter" }
        return LetterDeletionCopy.buttonTitle(for: letter, child: child(letter))
    }

    private var copyMessage: String {
        guard let letter = pendingLetter else { return "" }
        return LetterDeletionCopy.message(for: letter, child: child(letter))
    }

    private func confirm() {
        guard let letter = pendingLetter else { return }
        pendingLetter = nil
        switch LetterDeletion.perform(letter, in: context, child: child(letter)) {
        case .deleted:
            if let selection, selection.wrappedValue?.objectID == letter.objectID {
                selection.wrappedValue = nil
            }
            onDeleted?()
            dismissAction?()
        case .denied:
            // Defensive: the delete button is hidden when the user lacks
            // permission, so this is only reachable through a race.
            errorMessage = "You don't have permission to delete this letter."
        case .failed(let message):
            errorMessage = message
        }
    }
}

extension View {
    /// Attaches the letter delete confirmation dialog and failure alert.
    /// `pendingLetter` triggers the flow; copy is derived from the letter's
    /// state. On success, `selection` (if provided) is cleared, `onDeleted`
    /// fires, and `dismissAction` dismisses the presenting view.
    func letterDeletion(
        pendingLetter: Binding<Letter?>,
        errorMessage: Binding<String?>,
        child: @escaping (Letter) -> ChildProfile?,
        context: NSManagedObjectContext,
        selection: Binding<Letter?>? = nil,
        dismissAction: DismissAction? = nil,
        onDeleted: (() -> Void)? = nil
    ) -> some View {
        modifier(LetterDeletionModifier(
            pendingLetter: pendingLetter,
            errorMessage: errorMessage,
            child: child,
            context: context,
            selection: selection,
            dismissAction: dismissAction,
            onDeleted: onDeleted
        ))
    }
}

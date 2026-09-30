import Foundation

struct LibraryLetterSnapshot: Equatable {
    let id: UUID
    let childID: UUID?
    let title: String
    let body: String
    let authorName: String
    let isDraft: Bool
    let status: LetterStatus
}

enum LetterLibraryFilter {
    static func filter(
        _ letters: [LibraryLetterSnapshot],
        status: LetterStatus?,
        childID: UUID?,
        searchText: String
    ) -> [LibraryLetterSnapshot] {
        letters.filter { letter in
            let matchesChild = childID == nil || letter.childID == childID
            let matchesStatus = status == nil || letter.status == status
            // Sealed content must not leak through search. A scheduled letter
            // is sealed and locked, so its BODY is excluded from the haystack;
            // otherwise typing a phrase from a sealed letter would confirm its
            // contents to a viewer who cannot open it. Title/author stay
            // searchable because the row already renders them for sealed
            // letters. Drafts and unlocked letters keep full-body search.
            let isSealed = letter.status == .scheduled
            let matchesSearch = searchText.isEmpty
                || letter.title.localizedCaseInsensitiveContains(searchText)
                || (!isSealed && letter.body.localizedCaseInsensitiveContains(searchText))
                || letter.authorName.localizedCaseInsensitiveContains(searchText)
            return matchesChild && matchesStatus && matchesSearch
        }
    }
}

enum LetterSaveResult: Equatable {
    case saved
    case failed(String)
}

func saveLetter(_ operation: () throws -> Void) -> LetterSaveResult {
    do {
        try operation()
        return .saved
    } catch {
        return .failed(error.localizedDescription)
    }
}

enum LetterLifecycle {
    static func sealedDate(existing: Date?, sealed: Bool, now: Date) -> Date? {
        sealed ? (existing ?? now) : nil
    }
}

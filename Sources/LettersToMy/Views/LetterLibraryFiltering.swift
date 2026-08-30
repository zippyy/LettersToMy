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
            let matchesSearch = searchText.isEmpty
                || letter.title.localizedCaseInsensitiveContains(searchText)
                || letter.body.localizedCaseInsensitiveContains(searchText)
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

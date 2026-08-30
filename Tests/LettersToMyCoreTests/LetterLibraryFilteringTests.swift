import Foundation
import Testing
@testable import LettersToMy

@Suite(.serialized)
struct LetterLibraryFilteringTests {
    private let childA = UUID()
    private let childB = UUID()

    private func item(
        _ title: String,
        childID: UUID?,
        status: LetterStatus,
        body: String = "body",
        author: String = "author",
        draft: Bool = false
    ) -> LibraryLetterSnapshot {
        LibraryLetterSnapshot(
            id: UUID(),
            childID: childID,
            title: title,
            body: body,
            authorName: author,
            isDraft: draft,
            status: status
        )
    }

    @Test func allLettersAndAllChildrenReturnsEveryLetter() {
        let letters = [
            item("A", childID: childA, status: .scheduled),
            item("B", childID: childB, status: .unlocked),
            item("Unassigned", childID: nil, status: .draft, draft: true)
        ]
        #expect(LetterLibraryFilter.filter(letters, status: nil, childID: nil, searchText: "").count == 3)
    }

    @Test func statusFiltersRemainIndependentOfChildFilter() {
        let letters = [
            item("A scheduled", childID: childA, status: .scheduled),
            item("B scheduled", childID: childB, status: .scheduled),
            item("A unlocked", childID: childA, status: .unlocked),
            item("A draft", childID: childA, status: .draft, draft: true)
        ]
        #expect(LetterLibraryFilter.filter(letters, status: .scheduled, childID: nil, searchText: "").count == 2)
        #expect(LetterLibraryFilter.filter(letters, status: .scheduled, childID: childA, searchText: "").map(\.title) == ["A scheduled"])
        #expect(LetterLibraryFilter.filter(letters, status: .draft, childID: childA, searchText: "").map(\.title) == ["A draft"])
        #expect(LetterLibraryFilter.filter(letters, status: .unlocked, childID: childA, searchText: "").map(\.title) == ["A unlocked"])
    }

    @Test func searchAppliesAcrossTitleBodyAndAuthor() {
        let letters = [
            item("Birthday", childID: childA, status: .scheduled, body: "A special day"),
            item("School", childID: childB, status: .scheduled, author: "Grandma")
        ]
        #expect(LetterLibraryFilter.filter(letters, status: nil, childID: nil, searchText: "special").count == 1)
        #expect(LetterLibraryFilter.filter(letters, status: nil, childID: nil, searchText: "grandma").count == 1)
    }

    @Test func allChildrenDoesNotBecomeFirstChild() {
        let letters = [
            item("A", childID: childA, status: .scheduled),
            item("B", childID: childB, status: .scheduled)
        ]
        let all = LetterLibraryFilter.filter(letters, status: nil, childID: nil, searchText: "")
        #expect(all.map(\.title) == ["A", "B"])
    }

    @Test func failedSaveReturnsFailureWithoutReportingSuccess() {
        let result = saveLetter {
            throw NSError(domain: "TestSave", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        }
        #expect(result == .failed("disk full"))
        #expect(result != .saved)
    }
}

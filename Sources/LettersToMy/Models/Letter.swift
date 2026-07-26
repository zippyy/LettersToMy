import Foundation
import LettersToMyCore
import SwiftData

@Model
final class Letter {
    var id: UUID = UUID()
    var childID: UUID?
    var title: String = ""
    var body: String = ""
    var authorName: String = ""
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now
    var sealedAt: Date?
    var isFavorite: Bool = false

    var unlockRuleRawValue: String = UnlockRuleKind.specificDate.rawValue
    var unlockDate: Date?
    var unlockAgeYears: Int?
    var lifeEventName: String = ""
    var manuallyReleasedAt: Date?

    init(
        childID: UUID? = nil,
        title: String = "",
        body: String = "",
        authorName: String = ""
    ) {
        self.id = UUID()
        self.childID = childID
        self.title = title
        self.body = body
        self.authorName = authorName
        self.createdAt = Date.now
        self.updatedAt = Date.now
    }

    var unlockRuleKind: UnlockRuleKind {
        get { UnlockRuleKind(rawValue: unlockRuleRawValue) ?? .specificDate }
        set { unlockRuleRawValue = newValue.rawValue }
    }

    var schedule: LetterUnlockSchedule {
        LetterUnlockSchedule(
            kind: unlockRuleKind,
            specificDate: unlockDate,
            ageInYears: unlockAgeYears,
            lifeEventName: lifeEventName,
            manuallyReleasedAt: manuallyReleasedAt
        )
    }

    var isDraft: Bool { sealedAt == nil }

    func isUnlocked(for child: ChildProfile?, now: Date = .now) -> Bool {
        guard !isDraft else { return false }
        return schedule.isUnlocked(birthDate: child?.birthDate, now: now)
    }

    func status(for child: ChildProfile?, now: Date = .now) -> LetterStatus {
        if isDraft { return .draft }
        return isUnlocked(for: child, now: now) ? .unlocked : .scheduled
    }
}

enum LetterStatus: String, CaseIterable, Identifiable {
    case draft
    case scheduled
    case unlocked

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: "Draft"
        case .scheduled: "Scheduled"
        case .unlocked: "Unlocked"
        }
    }

    var systemImage: String {
        switch self {
        case .draft: "square.and.pencil"
        case .scheduled: "lock.fill"
        case .unlocked: "lock.open.fill"
        }
    }
}

import CoreData
import Foundation
import LettersToMyCore

@objc(Letter)
final class Letter: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var childID: UUID?
    @NSManaged var branchID: UUID?
    @NSManaged var folderID: UUID?
    @NSManaged var authorMemberID: UUID?
    @NSManaged var title: String
    @NSManaged var body: String
    @NSManaged var authorName: String
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var sealedAt: Date?
    @NSManaged var isFavorite: Bool
    @NSManaged var unlockRuleRawValue: String
    @NSManaged var unlockDate: Date?
    @NSManaged var unlockAgeYearsValue: NSNumber?
    @NSManaged var lifeEventName: String
    @NSManaged var manuallyReleasedAt: Date?
    @NSManaged var partition: SharePartitionRecord?
    @NSManaged var attachments: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        title = ""
        body = ""
        authorName = ""
        createdAt = .now
        updatedAt = .now
        isFavorite = false
        unlockRuleRawValue = UnlockRuleKind.specificDate.rawValue
        lifeEventName = ""
    }

    var unlockAgeYears: Int? {
        get { unlockAgeYearsValue?.intValue }
        set { unlockAgeYearsValue = newValue.map(NSNumber.init(value:)) }
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

    func collaborationContext(
        for child: ChildProfile?,
        now: Date = .now
    ) -> CollaborationContext {
        CollaborationContext(
            branchID: branchID,
            folderID: folderID,
            recipientID: childID,
            authorMemberID: authorMemberID,
            isSealed: !isDraft && !isUnlocked(for: child, now: now),
            isUnlocked: isUnlocked(for: child, now: now)
        )
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

import Foundation

public enum UnlockRuleKind: String, Codable, CaseIterable, Sendable {
    case specificDate
    case birthdayAge
    case lifeEvent

    public var title: String {
        switch self {
        case .specificDate: "Specific date"
        case .birthdayAge: "Birthday"
        case .lifeEvent: "Life event"
        }
    }
}

public struct LetterUnlockSchedule: Codable, Equatable, Sendable {
    public var kind: UnlockRuleKind
    public var specificDate: Date?
    public var ageInYears: Int?
    public var lifeEventName: String?
    public var manuallyReleasedAt: Date?

    public init(
        kind: UnlockRuleKind,
        specificDate: Date? = nil,
        ageInYears: Int? = nil,
        lifeEventName: String? = nil,
        manuallyReleasedAt: Date? = nil
    ) {
        self.kind = kind
        self.specificDate = specificDate
        self.ageInYears = ageInYears
        self.lifeEventName = lifeEventName
        self.manuallyReleasedAt = manuallyReleasedAt
    }

    public func resolvedDate(birthDate: Date?, calendar: Calendar = .current) -> Date? {
        switch kind {
        case .specificDate:
            return specificDate
        case .birthdayAge:
            guard let birthDate, let ageInYears else { return nil }
            return calendar.date(byAdding: .year, value: ageInYears, to: birthDate)
        case .lifeEvent:
            return manuallyReleasedAt
        }
    }

    public func isUnlocked(
        birthDate: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard let unlockDate = resolvedDate(birthDate: birthDate, calendar: calendar) else {
            return false
        }
        return unlockDate <= now
    }

    public func summary(birthDate: Date?, calendar: Calendar = .current) -> String {
        switch kind {
        case .specificDate:
            guard let specificDate else { return "Choose an unlock date" }
            return specificDate.formatted(date: .long, time: .omitted)
        case .birthdayAge:
            guard let ageInYears else { return "Choose a birthday" }
            return "Age \(ageInYears)"
        case .lifeEvent:
            if manuallyReleasedAt != nil {
                return "Released"
            }
            return lifeEventName?.isEmpty == false ? lifeEventName! : "Future life event"
        }
    }
}

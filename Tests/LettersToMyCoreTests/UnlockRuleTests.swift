import Foundation
import Testing
@testable import LettersToMyCore

struct UnlockRuleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test func specificDateUnlocksAtScheduledTime() {
        let unlockDate = Date(timeIntervalSince1970: 2_000)
        let schedule = LetterUnlockSchedule(kind: .specificDate, specificDate: unlockDate)

        #expect(!schedule.isUnlocked(birthDate: nil, now: Date(timeIntervalSince1970: 1_999)))
        #expect(schedule.isUnlocked(birthDate: nil, now: unlockDate))
    }

    @Test func birthdayUsesChildBirthDate() throws {
        let birthDate = Date(timeIntervalSince1970: 0)
        let schedule = LetterUnlockSchedule(kind: .birthdayAge, ageInYears: 5)
        let expected = try #require(calendar.date(byAdding: .year, value: 5, to: birthDate))

        #expect(schedule.resolvedDate(birthDate: birthDate, calendar: calendar) == expected)
        #expect(schedule.isUnlocked(birthDate: birthDate, now: expected, calendar: calendar))
    }

    @Test func lifeEventStaysLockedUntilReleased() {
        var schedule = LetterUnlockSchedule(kind: .lifeEvent, lifeEventName: "Wedding day")
        #expect(!schedule.isUnlocked(birthDate: nil))

        schedule.manuallyReleasedAt = Date(timeIntervalSince1970: 100)
        #expect(schedule.isUnlocked(birthDate: nil, now: Date(timeIntervalSince1970: 101)))
    }
}

import Foundation
import Testing
@testable import LettersToMyCore

struct DeliveryPipelineTests {
    private let childID = UUID()

    private func makeLetter(
        id: UUID = UUID(),
        title: String = "Test",
        body: String = "Body",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sealedAt: Date? = Date.distantPast,
        unlockRuleRawValue: String = "specificDate",
        unlockDate: Date? = Date.distantPast,
        unlockAgeYearsValue: Int? = nil,
        lifeEventName: String = "",
        manuallyReleasedAt: Date? = nil
    ) -> LetterPayload {
        LetterPayload(
            id: id,
            childID: childID,
            title: title,
            body: body,
            authorName: "Mom",
            createdAt: createdAt,
            updatedAt: updatedAt,
            sealedAt: sealedAt,
            unlockRuleRawValue: unlockRuleRawValue,
            unlockDate: unlockDate,
            unlockAgeYearsValue: unlockAgeYearsValue,
            lifeEventName: lifeEventName,
            manuallyReleasedAt: manuallyReleasedAt
        )
    }

    @Test func draftLetterIsNotDelivered() {
        let letter = makeLetter(sealedAt: nil)
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: nil,
            existingDeliveries: []
        )
        #expect(pending.isEmpty)
    }

    @Test func alreadyDeliveredLetterIsSkipped() {
        let letter = makeLetter()
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: nil,
            existingDeliveries: [letter.id]
        )
        #expect(pending.isEmpty)
    }

    @Test func specificDateLetterInPastUnlocks() {
        let letter = makeLetter(unlockDate: Date.distantPast)
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: nil,
            existingDeliveries: []
        )
        #expect(pending.count == 1)
    }

    @Test func specificDateLetterInFutureDoesNotUnlock() {
        let letter = makeLetter(unlockDate: Date.distantFuture)
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: nil,
            existingDeliveries: []
        )
        #expect(pending.isEmpty)
    }

    @Test func lifeEventLetterUnlocksWhenManuallyReleased() {
        let letter = makeLetter(
            unlockRuleRawValue: "lifeEvent",
            unlockDate: nil,
            lifeEventName: "Graduation",
            manuallyReleasedAt: Date.distantPast
        )
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: nil,
            existingDeliveries: []
        )
        #expect(pending.count == 1)
    }

    @Test func lifeEventLetterStaysLockedWithoutRelease() {
        let letter = makeLetter(
            unlockRuleRawValue: "lifeEvent",
            unlockDate: nil,
            lifeEventName: "Graduation",
            manuallyReleasedAt: nil
        )
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: nil,
            existingDeliveries: []
        )
        #expect(pending.isEmpty)
    }

    @Test func birthdayAgeLetterUnlocksWhenChildIsOldEnough() {
        let tenYearsAgo = Calendar.current.date(
            byAdding: .year, value: -10, to: .now
        )!
        let letter = makeLetter(
            unlockRuleRawValue: "birthdayAge",
            unlockDate: nil,
            unlockAgeYearsValue: 5
        )
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: tenYearsAgo,
            existingDeliveries: []
        )
        #expect(pending.count == 1)
    }

    @Test func birthdayAgeLetterDoesNotUnlockWhenTooYoung() {
        let twoYearsAgo = Calendar.current.date(
            byAdding: .year, value: -2, to: .now
        )!
        let letter = makeLetter(
            unlockRuleRawValue: "birthdayAge",
            unlockDate: nil,
            unlockAgeYearsValue: 18
        )
        let pending = DeliveryPipeline.pendingDeliveries(
            letters: [letter],
            childBirthDate: twoYearsAgo,
            existingDeliveries: []
        )
        #expect(pending.isEmpty)
    }

    @Test func prepareDeliveryCopiesFields() {
        let letter = makeLetter(title: "Dear Emma", body: "I love you")
        let delivery = DeliveryPipeline.prepareDelivery(
            from: letter,
            for: childID,
            attachments: [],
            existingDeliveries: []
        )

        #expect(delivery != nil)
        #expect(delivery?.title == "Dear Emma")
        #expect(delivery?.body == "I love you")
        #expect(delivery?.authorName == "Mom")
        #expect(delivery?.recipientID == childID)
        #expect(delivery?.originalLetterID == letter.id)
        #expect(delivery?.state == .delivered)
    }

    @Test func prepareDeliveryIncludesAttachments() {
        let letter = makeLetter()
        let attachment = AttachmentPayload(
            id: UUID(),
            letterID: letter.id,
            fileName: "photo.jpg",
            contentTypeIdentifier: "public.jpeg",
            kindRawValue: "photo",
            createdAt: .now,
            data: Data([0x01, 0x02, 0x03])
        )

        let delivery = DeliveryPipeline.prepareDelivery(
            from: letter,
            for: childID,
            attachments: [attachment],
            existingDeliveries: []
        )

        #expect(delivery?.attachments.count == 1)
        #expect(delivery?.attachments.first?.fileName == "photo.jpg")
        #expect(delivery?.attachments.first?.data == Data([0x01, 0x02, 0x03]))
    }

    @Test func prepareDeliveryIsIdempotent() {
        let letter = makeLetter()
        let first = DeliveryPipeline.prepareDelivery(
            from: letter,
            for: childID,
            attachments: [],
            existingDeliveries: []
        )
        let second = DeliveryPipeline.prepareDelivery(
            from: letter,
            for: childID,
            attachments: [],
            existingDeliveries: [letter.id]
        )

        #expect(first != nil)
        #expect(second == nil)
    }

    @Test func deliveryExcludesOtherChildrenLetters() {
        let otherLetter = makeLetter()
        let delivery = DeliveryPipeline.prepareDelivery(
            from: otherLetter,
            for: UUID(),
            attachments: [],
            existingDeliveries: []
        )
        #expect(delivery == nil)
    }
}

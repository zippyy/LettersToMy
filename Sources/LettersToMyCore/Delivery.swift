import Foundation
import LettersToMyCore

/// The delivery state of a single unlocked letter to a recipient inbox.
public enum DeliveryState: String, Codable, Sendable {
    case delivered
    case read
    case replied
}

/// A lightweight, read-only copy of an unlocked letter placed in a
/// recipient inbox partition. The recipient never sees the sealed
/// master record — only this controlled delivery representation.
public struct DeliveryRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var recipientID: UUID
    public var originalLetterID: UUID
    public var title: String
    public var body: String
    public var authorName: String
    public var deliveredAt: Date
    public var readAt: Date?
    public var replyBody: String?
    public var repliedAt: Date?
    public var state: DeliveryState
    public var attachments: [DeliveryAttachment]

    public init(
        id: UUID = UUID(),
        recipientID: UUID,
        originalLetterID: UUID,
        title: String,
        body: String,
        authorName: String,
        deliveredAt: Date = .now,
        readAt: Date? = nil,
        replyBody: String? = nil,
        repliedAt: Date? = nil,
        state: DeliveryState = .delivered,
        attachments: [DeliveryAttachment] = []
    ) {
        self.id = id
        self.recipientID = recipientID
        self.originalLetterID = originalLetterID
        self.title = title
        self.body = body
        self.authorName = authorName
        self.deliveredAt = deliveredAt
        self.readAt = readAt
        self.replyBody = replyBody
        self.repliedAt = repliedAt
        self.state = state
        self.attachments = attachments
    }
}

/// A copy of an attachment placed inside a delivery. The data is
/// copied from the master attachment so the recipient never gains
/// access to the sealed store.
public struct DeliveryAttachment: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var fileName: String
    public var contentTypeIdentifier: String
    public var kindRawValue: String
    public var data: Data

    public init(
        id: UUID = UUID(),
        fileName: String,
        contentTypeIdentifier: String,
        kindRawValue: String,
        data: Data
    ) {
        self.id = id
        self.fileName = fileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.kindRawValue = kindRawValue
        self.data = data
    }
}

// MARK: - Delivery Pipeline

/// The delivery pipeline evaluates unlock rules and creates recipient
/// deliveries when letters become available. It is idempotent —
/// repeated calls do not duplicate deliveries.
public enum DeliveryPipeline {
    /// Build a delivery payload for a letter that has just unlocked.
    /// Returns nil if a delivery already exists for this letter+recipient
    /// pair, ensuring idempotency.
    public static func prepareDelivery(
        from letter: LetterPayload,
        for recipientID: UUID,
        attachments: [AttachmentPayload],
        existingDeliveries: [UUID]  // existing delivery originalLetterIDs
    ) -> DeliveryRecord? {
        // Idempotency: skip if already delivered.
        guard !existingDeliveries.contains(letter.id) else { return nil }

        // Only deliver if the letter is sealed (not a draft) and the
        // recipient matches.
        guard letter.sealedAt != nil, letter.childID == recipientID else {
            return nil
        }

        let deliveryAttachments = attachments
            .filter { $0.letterID == letter.id }
            .map {
                DeliveryAttachment(
                    id: UUID(),
                    fileName: $0.fileName,
                    contentTypeIdentifier: $0.contentTypeIdentifier,
                    kindRawValue: $0.kindRawValue,
                    data: $0.data
                )
            }

        return DeliveryRecord(
            recipientID: recipientID,
            originalLetterID: letter.id,
            title: letter.title,
            body: letter.body,
            authorName: letter.authorName,
            deliveredAt: .now,
            attachments: deliveryAttachments
        )
    }

    /// Determine which letters need delivery by evaluating unlock rules.
    /// Returns the set of letter IDs that have unlocked but not yet been
    /// delivered.
    public static func pendingDeliveries(
        letters: [LetterPayload],
        childBirthDate: Date?,
        existingDeliveries: [UUID],
        now: Date = .now
    ) -> [LetterPayload] {
        let deliveredIDs = Set(existingDeliveries)
        return letters.filter { letter in
            guard letter.sealedAt != nil else { return false }
            guard !deliveredIDs.contains(letter.id) else { return false }

            let schedule = LetterUnlockSchedule(
                kind: UnlockRuleKind(rawValue: letter.unlockRuleRawValue) ?? .specificDate,
                specificDate: letter.unlockDate,
                ageInYears: letter.unlockAgeYearsValue,
                lifeEventName: letter.lifeEventName,
                manuallyReleasedAt: letter.manuallyReleasedAt
            )
            return schedule.isUnlocked(birthDate: childBirthDate, now: now)
        }
    }
}

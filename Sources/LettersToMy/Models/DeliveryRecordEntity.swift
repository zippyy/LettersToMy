import CoreData
import Foundation
import LettersToMyCore

@objc(DeliveryRecordEntity)
final class DeliveryRecordEntity: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var recipientID: UUID
    @NSManaged var originalLetterID: UUID
    @NSManaged var title: String
    @NSManaged var body: String
    @NSManaged var authorName: String
    @NSManaged var deliveredAt: Date
    @NSManaged var readAt: Date?
    @NSManaged var replyBody: String?
    @NSManaged var repliedAt: Date?
    @NSManaged var stateRawValue: String
    @NSManaged var partition: SharePartitionRecord?
    @NSManaged var deliveryAttachments: NSSet?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        recipientID = UUID()
        originalLetterID = UUID()
        title = ""
        body = ""
        authorName = ""
        deliveredAt = .now
        stateRawValue = DeliveryState.delivered.rawValue
    }

    var state: DeliveryState {
        get { DeliveryState(rawValue: stateRawValue) ?? .delivered }
        set { stateRawValue = newValue.rawValue }
    }

    var attachments: [DeliveryAttachmentEntity] {
        (deliveryAttachments?.allObjects as? [DeliveryAttachmentEntity] ?? [])
            .sorted { $0.fileName < $1.fileName }
    }
}

@objc(DeliveryAttachmentEntity)
final class DeliveryAttachmentEntity: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var fileName: String
    @NSManaged var contentTypeIdentifier: String
    @NSManaged var kindRawValue: String
    @NSManaged var data: Data?
    @NSManaged var delivery: DeliveryRecordEntity?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        fileName = "Attachment"
        contentTypeIdentifier = "public.data"
        kindRawValue = AttachmentKind.file.rawValue
    }
}

import CoreData
import Foundation
import LettersToMyCore

@objc(BackupRecordEntity)
final class BackupRecordEntity: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var destinationRawValue: String
    @NSManaged var statusRawValue: String
    @NSManaged var createdAt: Date
    @NSManaged var completedAt: Date?
    @NSManaged var sizeBytes: Int64
    @NSManaged var letterCount: Int64
    @NSManaged var attachmentCount: Int64
    @NSManaged var errorMessage: String?
    @NSManaged var remoteIdentifier: String?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        destinationRawValue = BackupDestination.localFile.rawValue
        statusRawValue = BackupStatus.completed.rawValue
        createdAt = .now
        sizeBytes = 0
        letterCount = 0
        attachmentCount = 0
    }

    var destination: BackupDestination {
        get { BackupDestination(rawValue: destinationRawValue) ?? .localFile }
        set { destinationRawValue = newValue.rawValue }
    }

    var status: BackupStatus {
        get { BackupStatus(rawValue: statusRawValue) ?? .completed }
        set { statusRawValue = newValue.rawValue }
    }

    var domainRecord: BackupRecord {
        BackupRecord(
            id: id,
            destination: destination,
            status: status,
            createdAt: createdAt,
            completedAt: completedAt,
            sizeBytes: sizeBytes,
            letterCount: Int(letterCount),
            attachmentCount: Int(attachmentCount),
            errorMessage: errorMessage,
            remoteIdentifier: remoteIdentifier
        )
    }

    func apply(_ record: BackupRecord) {
        id = record.id
        destination = record.destination
        status = record.status
        createdAt = record.createdAt
        completedAt = record.completedAt
        sizeBytes = record.sizeBytes
        letterCount = Int64(record.letterCount)
        attachmentCount = Int64(record.attachmentCount)
        errorMessage = record.errorMessage
        remoteIdentifier = record.remoteIdentifier
    }
}

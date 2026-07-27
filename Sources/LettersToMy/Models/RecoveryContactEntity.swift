import CoreData
import Foundation

/// A trusted person designated to recover the archive if the owner
/// becomes incapacitated or loses access. CloudKit recovery contacts
/// are handled through Apple's account recovery; this record
/// supplements that with archive-specific instructions.
@objc(RecoveryContactEntity)
final class RecoveryContactEntity: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var displayName: String
    @NSManaged var emailAddress: String
    @NSManaged var phoneNumber: String?
    @NSManaged var relationship: String
    @NSManaged var recoveryKeyHash: Data?
    @NSManaged var notes: String?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        displayName = ""
        emailAddress = ""
        relationship = ""
        createdAt = .now
        updatedAt = .now
    }
}

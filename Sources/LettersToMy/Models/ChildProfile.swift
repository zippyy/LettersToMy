import CoreData
import Foundation

@objc(ChildProfile)
final class ChildProfile: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var name: String
    @NSManaged var birthDate: Date?
    @NSManaged var createdAt: Date
    @NSManaged var updatedAt: Date
    @NSManaged var partition: SharePartitionRecord?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        name = ""
        createdAt = .now
        updatedAt = .now
    }
}

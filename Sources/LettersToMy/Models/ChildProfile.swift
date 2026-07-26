import Foundation
import SwiftData

@Model
final class ChildProfile {
    var id: UUID = UUID()
    var name: String = ""
    var birthDate: Date?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(name: String = "", birthDate: Date? = nil) {
        self.id = UUID()
        self.name = name
        self.birthDate = birthDate
        self.createdAt = Date.now
        self.updatedAt = Date.now
    }
}

import CoreData
import Foundation

@objc(LetterAttachment)
final class LetterAttachment: NSManagedObject, Identifiable {
    @NSManaged var id: UUID
    @NSManaged var letterID: UUID
    @NSManaged var fileName: String
    @NSManaged var contentTypeIdentifier: String
    @NSManaged var createdAt: Date
    @NSManaged var kindRawValue: String
    @NSManaged var data: Data?
    @NSManaged var letter: Letter?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        id = UUID()
        letterID = UUID()
        fileName = "Attachment"
        contentTypeIdentifier = "public.data"
        createdAt = .now
        kindRawValue = AttachmentKind.file.rawValue
    }

    var kind: AttachmentKind {
        get { AttachmentKind(rawValue: kindRawValue) ?? .file }
        set { kindRawValue = newValue.rawValue }
    }
}

enum AttachmentKind: String, CaseIterable {
    case photo
    case video
    case audio
    case file

    var systemImage: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .audio: "waveform"
        case .file: "doc"
        }
    }
}

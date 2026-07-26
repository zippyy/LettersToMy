import Foundation
import SwiftData

@Model
final class LetterAttachment {
    var id: UUID = UUID()
    var letterID: UUID = UUID()
    var fileName: String = "Attachment"
    var contentTypeIdentifier: String = "public.data"
    var createdAt: Date = Date.now
    var kindRawValue: String = AttachmentKind.file.rawValue

    @Attribute(.externalStorage)
    var data: Data?

    init(
        letterID: UUID,
        fileName: String,
        contentTypeIdentifier: String,
        kind: AttachmentKind,
        data: Data
    ) {
        self.id = UUID()
        self.letterID = letterID
        self.fileName = fileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.createdAt = Date.now
        self.kindRawValue = kind.rawValue
        self.data = data
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

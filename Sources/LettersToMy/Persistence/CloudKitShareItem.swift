import CloudKit
import CoreTransferable
import Foundation

struct CloudKitShareItem: Transferable, Sendable {
    let partitionURI: URL
    let title: String

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            let persistence = PersistenceController.shared
            if let existing = try persistence.existingShare(for: item.partitionURI) {
                return .existing(existing, container: persistence.ckContainer)
            }

            return .prepareShare(container: persistence.ckContainer) {
                try await persistence.prepareShare(
                    for: item.partitionURI,
                    title: item.title
                )
            }
        }
    }
}
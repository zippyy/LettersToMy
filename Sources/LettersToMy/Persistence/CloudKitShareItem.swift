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
                return .existing(existing, container: persistence.cloudKitContainer)
            }

            return .prepareShare(container: persistence.cloudKitContainer) {
                try await persistence.prepareShare(
                    for: item.partitionURI,
                    title: item.title
                )
            }
        }
    }
}

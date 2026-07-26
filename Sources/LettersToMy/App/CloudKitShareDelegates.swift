import CloudKit
import Foundation
import LettersToMyCore

#if os(iOS)
import UIKit

final class LettersToMyApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "LettersToMy Scene",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = LettersToMySceneDelegate.self
        return configuration
    }
}

final class LettersToMySceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        let participantIdentity = participantIdentity(from: cloudKitShareMetadata)
        let persistence = PersistenceController.shared
        persistence.acceptShare(cloudKitShareMetadata) { result in
            if case .success = result {
                persistence.activateAcceptedMembers(
                    participantIdentity: participantIdentity
                )
            }
        }
    }
}

#elseif os(macOS)
import AppKit

final class LettersToMyApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        let participantIdentity = participantIdentity(from: metadata)
        let persistence = PersistenceController.shared
        persistence.acceptShare(metadata) { result in
            if case .success = result {
                persistence.activateAcceptedMembers(
                    participantIdentity: participantIdentity
                )
            }
        }
    }
}
#endif

/// Extract verified owner identity from share metadata.
/// The accepting participant's own CloudKit identity is resolved
/// separately and merged into the member record later.
private func participantIdentity(
    from metadata: CKShare.Metadata
) -> VerifiedParticipantIdentity? {
    let ownerIdentity = metadata.ownerIdentity
    let recordName = ownerIdentity.userRecordID?.recordName
        ?? ownerIdentity.lookupInfo?.emailAddress
        ?? ownerIdentity.lookupInfo?.phoneNumber
        ?? "unknown"

    return VerifiedParticipantIdentity(
        userRecordName: recordName,
        participantType: "share_participant"
    )
}

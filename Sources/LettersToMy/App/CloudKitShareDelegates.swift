import CloudKit
import Foundation
import LettersToMyCore

#if os(iOS)
import FirebaseCore
import FirebaseAnalytics
import UIKit

final class LettersToMyApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }

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
        let persistence = PersistenceController.shared
        persistence.acceptShare(cloudKitShareMetadata) { result in
            if case .success = result {
                // The accepting participant's own identity is NOT derivable
                // from share metadata (which exposes only the share owner),
                // so resolve it from the user's own CloudKit container
                // before creating the member record.
                Task {
                    let identity = await persistence.currentUserIdentity()
                    persistence.activateAcceptedMembers(
                        participantIdentity: identity
                    )
                }
            }
        }
    }
}

#elseif os(macOS)
import AppKit
import FirebaseCore

final class LettersToMyApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        FirebaseApp.configure()
    }

    func application(
        _ application: NSApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        let persistence = PersistenceController.shared
        persistence.acceptShare(metadata) { result in
            if case .success = result {
                // See iOS note: the acceptee's identity must come from
                // their own container, not from share metadata.
                Task {
                    let identity = await persistence.currentUserIdentity()
                    persistence.activateAcceptedMembers(
                        participantIdentity: identity
                    )
                }
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

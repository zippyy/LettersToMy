import CloudKit

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
        PersistenceController.shared.acceptShare(cloudKitShareMetadata)
    }
}

#elseif os(macOS)
import AppKit

final class LettersToMyApplicationDelegate: NSObject, NSApplicationDelegate {
    func application(
        _ application: NSApplication,
        userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
    ) {
        PersistenceController.shared.acceptShare(metadata)
    }
}
#endif

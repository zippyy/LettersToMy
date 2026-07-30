import Foundation
#if os(iOS)
import FirebaseAnalytics
#endif

/// Lightweight analytics wrapper. All Firebase calls are iOS-only;
/// macOS builds compile the stubs without linking Firebase.
enum Analytics {

    // MARK: - Lifecycle

    static func appOpened() {
        logEvent("app_opened", params: nil)
    }

    // MARK: - Content

    static func letterCreated(sealed: Bool, hasAttachments: Bool) {
        logEvent("letter_created", params: [
            "sealed": sealed ? "true" : "false",
            "has_attachments": hasAttachments ? "true" : "false"
        ])
    }

    static func letterEdited() {
        logEvent("letter_edited", params: nil)
    }

    static func letterUnlocked() {
        logEvent("letter_unlocked", params: nil)
    }

    static func attachmentAdded(kind: String) {
        logEvent("attachment_added", params: ["kind": kind])
    }

    // MARK: - Collaboration

    static func invitationCreated(role: String) {
        logEvent("invitation_created", params: ["role": role])
    }

    static func invitationSent() {
        logEvent("invitation_sent", params: nil)
    }

    static func invitationAccepted() {
        logEvent("invitation_accepted", params: nil)
    }

    static func invitationRevoked() {
        logEvent("invitation_revoked", params: nil)
    }

    // MARK: - Backup

    static func backupCompleted(destination: String, sizeBytes: Int64) {
        logEvent("backup_completed", params: [
            "destination": destination,
            "size_bytes": "\(sizeBytes)"
        ])
    }

    static func backupRestored(letterCount: Int) {
        logEvent("backup_restored", params: [
            "letter_count": "\(letterCount)"
        ])
    }

    // MARK: - Internal

    private static func logEvent(_ name: String, params: [String: String]?) {
        #if os(iOS)
        if let params {
            Analytics.logEvent(name, parameters: params)
        } else {
            Analytics.logEvent(name, parameters: nil)
        }
        #endif
    }
}
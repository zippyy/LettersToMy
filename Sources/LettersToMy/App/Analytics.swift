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

    static func onboardingCompleted() {
        logEvent("onboarding_completed", params: nil)
    }

    // MARK: - Screen Views

    static func screenView(_ screen: String) {
        logEvent("screen_view", params: ["screen_name": screen])
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

    static func letterSealed() {
        logEvent("letter_sealed", params: nil)
    }

    static func letterUnlocked() {
        logEvent("letter_unlocked", params: nil)
    }

    static func attachmentAdded(kind: String) {
        logEvent("attachment_added", params: ["kind": kind])
    }

    // MARK: - Family Structure

    static func childAdded() {
        logEvent("child_added", params: nil)
    }

    static func familySideAdded() {
        logEvent("family_side_added", params: nil)
    }

    static func folderAdded() {
        logEvent("folder_added", params: nil)
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

    // MARK: - Settings

    static func iconChanged(_ iconName: String) {
        logEvent("icon_changed", params: ["icon": iconName])
    }

    static func recipientPreviewToggled(_ enabled: Bool) {
        logEvent("recipient_preview_toggled", params: ["enabled": enabled ? "true" : "false"])
    }

    // MARK: - Errors

    static func error(_ domain: String, message: String) {
        logEvent("app_error", params: [
            "domain": domain,
            "message": message
        ])
    }

    // MARK: - Internal

    private static func logEvent(_ name: String, params: [String: String]?) {
        #if os(iOS)
        Analytics.logEvent(name, params: params)
        #endif
    }
}
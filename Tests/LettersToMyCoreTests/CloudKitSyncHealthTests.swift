import CloudKit
import Foundation
import Testing
@testable import LettersToMy

@Suite(.serialized)
struct CloudKitSyncHealthTests {
    private func partialFailure(item: String? = nil) -> NSError {
        var userInfo: [String: Any] = [:]
        if let item {
            userInfo[CKPartialErrorsByItemIDKey] = [item: NSError(
                domain: CKError.errorDomain,
                code: CKError.Code.serverRejectedRequest.rawValue
            )]
        }
        return NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: userInfo
        )
    }

    private func event(
        kind: CloudKitSyncEventSnapshot.Kind,
        succeeded: Bool,
        classification: CloudKitFailureClassification?,
        diagnostic: String? = "diagnostic",
        date: Date = Date(),
        isOpaquePartialFailure: Bool = false
    ) -> CloudKitSyncEventSnapshot {
        CloudKitSyncEventSnapshot(
            kind: kind,
            succeeded: succeeded,
            date: date,
            classification: classification,
            diagnostic: diagnostic,
            isOpaquePartialFailure: isOpaquePartialFailure
        )
    }

    @Test func systemManagedPartialFailureIsRetryingNotActionable() {
        let error = partialFailure(item: "_pcs_data")
        #expect(CloudKitFailureClassifier.classify(error) == .systemManaged)

        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .systemManaged))
        #expect(health.status == .retrying)
        #expect(health.userFacingMessage?.contains("retry automatically") == true)
    }

    @Test func appRecordPartialFailureRemainsActionable() {
        let error = partialFailure(item: "CD_Letter")
        #expect(CloudKitFailureClassifier.classify(error) == .actionable)

        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .actionable))
        #expect(health.status == .needsAttention)
        #expect(health.userFacingMessage?.contains("LettersToMy data") == true)
    }

    @Test func opaquePartialFailureIsNotAssumedToBeSystemManaged() {
        let error = partialFailure()
        #expect(CloudKitFailureClassifier.classify(error) == .transient)

        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .transient, diagnostic: nil, isOpaquePartialFailure: true))
        #expect(health.status == .retrying)
        #expect(health.lastErrorClassification == .transient)
    }

    @Test func successfulExportClearsOpaqueWarning() {
        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .transient, diagnostic: nil, isOpaquePartialFailure: true))
        health.apply(event(kind: .export, succeeded: true, classification: nil, diagnostic: nil))
        #expect(health.status == .healthy)
        #expect(health.lastError == nil)
        #expect(health.userFacingMessage == nil)
    }

    @Test func repeatedAppFailureRemainsVisible() {
        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .actionable))
        health.apply(event(kind: .export, succeeded: false, classification: .actionable))
        #expect(health.status == .needsAttention)
        #expect(health.lastErrorClassification == .actionable)
    }

    @Test func successfulImportDoesNotClearExportFailure() {
        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .actionable))
        health.apply(event(kind: .importEvent, succeeded: true, classification: nil, diagnostic: nil))
        #expect(health.status == .needsAttention)
        #expect(health.lastErrorClassification == .actionable)
    }

    @Test func olderEventCannotRegressNewerRecovery() {
        var health = CloudKitSyncHealth()
        let newer = Date(timeIntervalSince1970: 200)
        let older = Date(timeIntervalSince1970: 100)
        health.apply(event(kind: .export, succeeded: true, classification: nil, diagnostic: nil, date: newer))
        health.apply(event(kind: .export, succeeded: false, classification: .actionable, date: older))
        #expect(health.status == .healthy)
        #expect(health.lastError == nil)
    }

    @Test func repeatedOpaqueFailureEscalatesConservatively() {
        var health = CloudKitSyncHealth()
        for _ in 0..<3 {
            health.apply(event(kind: .export, succeeded: false, classification: .transient, diagnostic: "opaque", isOpaquePartialFailure: true))
        }
        #expect(health.status == .needsAttention)
        #expect(health.lastErrorClassification == .unknown)
    }

    @Test func accountAvailabilityDoesNotOverrideSyncFailure() {
        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .actionable))
        #expect(health.status == .needsAttention)
        // Account status is intentionally a separate PersistenceController
        // property; it cannot clear this health state by itself.
    }

    @Test func transientNetworkFailureRecoversOnExport() {
        var health = CloudKitSyncHealth()
        health.apply(event(kind: .export, succeeded: false, classification: .network))
        #expect(health.status == .retrying)
        health.apply(event(kind: .export, succeeded: true, classification: nil, diagnostic: nil))
        #expect(health.status == .healthy)
        #expect(health.lastError == nil)
    }
}

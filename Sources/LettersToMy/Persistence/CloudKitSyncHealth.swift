import CloudKit
import Foundation

/// The user-facing health of Core Data's CloudKit synchronization.
enum CloudKitSyncStatus: Equatable {
    case idle
    case syncing
    case healthy
    case retrying
    case needsAttention

    var userFacingLabel: String {
        switch self {
        case .idle: "Not started"
        case .syncing: "Syncing…"
        case .healthy: "Up to date"
        case .retrying: "Retrying"
        case .needsAttention: "Needs attention"
        }
    }
}

enum CloudKitFailureClassification: Equatable {
    case actionable
    case transient
    case systemManaged
    case account
    case network
    case quota
    case authentication
    case unknown

    var isUserActionable: Bool {
        switch self {
        case .actionable, .quota, .authentication, .unknown: true
        case .transient, .systemManaged, .account, .network: false
        }
    }
}

struct CloudKitSyncEventSnapshot {
    enum Kind: Equatable {
        case setup
        case importEvent
        case export
    }

    let kind: Kind
    let succeeded: Bool
    let date: Date
    let classification: CloudKitFailureClassification?
    let diagnostic: String?
    let isOpaquePartialFailure: Bool

    init(
        kind: Kind,
        succeeded: Bool,
        date: Date,
        classification: CloudKitFailureClassification?,
        diagnostic: String?,
        isOpaquePartialFailure: Bool = false
    ) {
        self.kind = kind
        self.succeeded = succeeded
        self.date = date
        self.classification = classification
        self.diagnostic = diagnostic
        self.isOpaquePartialFailure = isOpaquePartialFailure
    }
}

/// State machine for sync health. It deliberately does not equate one failed
/// event with permanently broken synchronization.
struct CloudKitSyncHealth: Equatable {
    private(set) var status: CloudKitSyncStatus = .idle
    private(set) var lastSuccessfulSetup: Date?
    private(set) var lastSuccessfulImport: Date?
    private(set) var lastSuccessfulExport: Date?
    private(set) var lastError: String?
    private(set) var lastErrorDate: Date?
    private(set) var lastErrorClassification: CloudKitFailureClassification?

    private struct Issue: Equatable {
        let classification: CloudKitFailureClassification
        let diagnostic: String?
        let date: Date
    }

    private var issues: [CloudKitSyncEventSnapshot.Kind: Issue] = [:]
    private var lastEventDates: [CloudKitSyncEventSnapshot.Kind: Date] = [:]
    private var consecutiveOpaqueFailures = 0

    mutating func apply(_ event: CloudKitSyncEventSnapshot) {
        // Notification delivery is asynchronous. Ignore an older event so it
        // cannot resurrect a stale error after a newer successful event.
        if let lastDate = lastEventDates[event.kind], event.date < lastDate { return }
        lastEventDates[event.kind] = event.date

        if event.succeeded {
            switch event.kind {
            case .setup: lastSuccessfulSetup = event.date
            case .importEvent: lastSuccessfulImport = event.date
            case .export: lastSuccessfulExport = event.date
            }
            issues.removeValue(forKey: event.kind)
            consecutiveOpaqueFailures = 0
            recomputeStatus()
            return
        }

        guard let classification = event.classification else { return }
        if classification == .transient && event.isOpaquePartialFailure {
            consecutiveOpaqueFailures += 1
        } else if classification != .transient {
            consecutiveOpaqueFailures = 0
        }

        let effectiveClassification: CloudKitFailureClassification =
            classification == .transient && event.isOpaquePartialFailure && consecutiveOpaqueFailures >= 3
                ? .unknown
                : classification
        issues[event.kind] = Issue(
            classification: effectiveClassification,
            diagnostic: event.diagnostic,
            date: event.date
        )
        recomputeStatus()
    }

    private mutating func recomputeStatus() {
        let currentIssues = Array(issues.values)
        if currentIssues.contains(where: { $0.classification.isUserActionable }) {
            status = .needsAttention
        } else if !currentIssues.isEmpty {
            status = .retrying
        } else if lastSuccessfulSetup != nil || lastSuccessfulImport != nil || lastSuccessfulExport != nil {
            status = .healthy
        } else {
            status = .idle
        }

        if let latest = currentIssues.max(by: { $0.date < $1.date }) {
            lastError = latest.diagnostic
            lastErrorDate = latest.date
            lastErrorClassification = latest.classification
        } else {
            lastError = nil
            lastErrorDate = nil
            lastErrorClassification = nil
        }
    }

    var userFacingMessage: String? {
        switch status {
        case .retrying:
            return "iCloud is available. Apple CloudKit reported a temporary sync issue; LettersToMy will retry automatically."
        case .needsAttention:
            return "Some LettersToMy data could not sync. Check your iCloud connection and try again."
        case .idle, .syncing, .healthy:
            return nil
        }
    }
}

/// Classifies CloudKit failures using structured error data where available.
/// Unknown/opaque partial failures remain conservative and transient.
enum CloudKitFailureClassifier {
    static func classify(_ error: Error) -> CloudKitFailureClassification {
        let chain = errorChain(error)
        if chain.contains(where: { ($0 as NSError).domain == CKError.errorDomain && ($0 as NSError).code == CKError.Code.partialFailure.rawValue }) {
            let identifiers = partialFailureItemIdentifiers(in: chain)
            let containsAppRecord = identifiers.contains { identifier in
                appOwnedRecordNames.contains { identifier.localizedCaseInsensitiveContains($0) }
            }
            let containsSystemRecord = identifiers.contains {
                $0.localizedCaseInsensitiveContains("_pcs_data")
            }

            // Never hide an app-owned rejection, even if a batch also contains
            // a system-managed item.
            if containsAppRecord { return .actionable }
            if containsSystemRecord { return .systemManaged }
            return .transient
        }

        if chain.contains(where: { ($0 as NSError).domain == NSURLErrorDomain }) {
            return .network
        }
        guard let nsError = chain.map({ $0 as NSError }).first(where: { $0.domain == CKError.errorDomain }) else {
            return .unknown
        }
        switch CKError.Code(rawValue: nsError.code) {
        case .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .notAuthenticated:
            return nsError.code == CKError.Code.notAuthenticated.rawValue ? .authentication : .network
        case .quotaExceeded:
            return .quota
        case .badContainer, .badDatabase, .permissionFailure, .constraintViolation, .unknownItem:
            return .actionable
        default:
            return .unknown
        }
    }

    static func isPartialFailure(_ error: Error) -> Bool {
        errorChain(error).contains {
            let nsError = $0 as NSError
            return nsError.domain == CKError.errorDomain && nsError.code == CKError.Code.partialFailure.rawValue
        }
    }

    private static let appOwnedRecordNames = [
        "CD_Letter", "CD_ChildProfile", "CD_LetterAttachment",
        "CD_FamilyBranchRecord", "CD_ArchiveFolderRecord", "CD_ArchiveMemberRecord",
        "CD_CollaborationInvitationRecord", "CD_SharePartitionRecord",
        "CD_BackupRecordEntity", "CD_DeliveryRecordEntity",
        "CD_DeliveryAttachmentEntity", "CD_RecoveryContactEntity"
    ]

    private static func errorChain(_ error: Error) -> [Error] {
        var result: [Error] = []
        var current: Error? = error
        var seen = Set<String>()
        while let value = current {
            let nsError = value as NSError
            let marker = "\(nsError.domain):\(nsError.code):\(nsError.localizedDescription)"
            guard seen.insert(marker).inserted else { break }
            result.append(value)
            current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return result
    }

    private static func partialFailureItemIdentifiers(in errors: [Error]) -> [String] {
        errors.flatMap { error in
            let nsError = error as NSError
            guard nsError.domain == CKError.errorDomain,
                  nsError.code == CKError.Code.partialFailure.rawValue,
                  let raw = nsError.userInfo[CKPartialErrorsByItemIDKey] else { return [String]() }
            if let dictionary = raw as? [AnyHashable: Any] {
                return dictionary.keys.map(recordIdentifier)
            }
            if let dictionary = raw as? NSDictionary {
                return dictionary.allKeys.map(recordIdentifier)
            }
            return []
        }
    }

    private static func recordIdentifier(_ value: Any) -> String {
        if let recordID = value as? CKRecord.ID { return recordID.recordName }
        return String(describing: value)
    }
}

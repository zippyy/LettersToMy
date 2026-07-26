import Foundation

// MARK: - Backup Destination

/// Identifies a backup storage backend. The application layer provides
/// concrete implementations for each destination that the current
/// platform supports.
public enum BackupDestination: String, Codable, CaseIterable, Sendable {
    case localFile
    case iCloudDrive
    case googleDrive
    case synologyNAS
    case nextcloud
    case s3Compatible
    case webDAV

    public var title: String {
        switch self {
        case .localFile: "Local File"
        case .iCloudDrive: "iCloud Drive"
        case .googleDrive: "Google Drive"
        case .synologyNAS: "Synology NAS"
        case .nextcloud: "Nextcloud"
        case .s3Compatible: "S3 Compatible"
        case .webDAV: "WebDAV"
        }
    }

    public var systemImage: String {
        switch self {
        case .localFile: "folder"
        case .iCloudDrive: "icloud"
        case .googleDrive: "externaldrive.badge.icloud"
        case .synologyNAS: "server.rack"
        case .nextcloud: "cloud"
        case .s3Compatible: "externaldrive"
        case .webDAV: "network"
        }
    }
}

// MARK: - Backup Configuration

/// Per‑destination backup settings stored in the archive and
/// persisted alongside backup records.
public struct BackupConfiguration: Codable, Equatable, Sendable {
    public var destination: BackupDestination
    public var enabled: Bool
    public var label: String
    public var scheduleInterval: TimeInterval?
    public var retentionCount: Int
    public var lastBackupAt: Date?
    public var lastBackupStatus: BackupStatus?

    /// Provider‑specific connection parameters. Encrypted at rest.
    public var endpointURL: String?
    public var username: String?
    public var credential: Data?

    public init(
        destination: BackupDestination,
        enabled: Bool = false,
        label: String = "",
        scheduleInterval: TimeInterval? = nil,
        retentionCount: Int = 5,
        lastBackupAt: Date? = nil,
        lastBackupStatus: BackupStatus? = nil,
        endpointURL: String? = nil,
        username: String? = nil,
        credential: Data? = nil
    ) {
        self.destination = destination
        self.enabled = enabled
        self.label = label.isEmpty ? destination.title : label
        self.scheduleInterval = scheduleInterval
        self.retentionCount = retentionCount
        self.lastBackupAt = lastBackupAt
        self.lastBackupStatus = lastBackupStatus
        self.endpointURL = endpointURL
        self.username = username
        self.credential = credential
    }
}

// MARK: - Backup Status

public enum BackupStatus: String, Codable, Sendable {
    case inProgress
    case completed
    case failed
    case cancelled

    public var title: String {
        switch self {
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

// MARK: - Backup Record

/// Lightweight metadata about a single backup operation.
/// Persisted locally so the user can browse history without
/// connecting to the remote provider.
public struct BackupRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var destination: BackupDestination
    public var status: BackupStatus
    public var createdAt: Date
    public var completedAt: Date?
    public var sizeBytes: Int64
    public var letterCount: Int
    public var attachmentCount: Int
    public var errorMessage: String?
    public var remoteIdentifier: String?

    public init(
        id: UUID = UUID(),
        destination: BackupDestination,
        status: BackupStatus = .inProgress,
        createdAt: Date = .now,
        completedAt: Date? = nil,
        sizeBytes: Int64 = 0,
        letterCount: Int = 0,
        attachmentCount: Int = 0,
        errorMessage: String? = nil,
        remoteIdentifier: String? = nil
    ) {
        self.id = id
        self.destination = destination
        self.status = status
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sizeBytes = sizeBytes
        self.letterCount = letterCount
        self.attachmentCount = attachmentCount
        self.errorMessage = errorMessage
        self.remoteIdentifier = remoteIdentifier
    }
}

// MARK: - Backup Manifest

/// Unencrypted header written at the top of every archive so the
/// user (or a recovery tool) can identify the backup without the
/// decryption key.
public struct BackupManifest: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var archiveID: UUID
    public var createdAt: Date
    public var appVersion: String
    public var letterCount: Int
    public var attachmentCount: Int
    public var recipientCount: Int
    public var encryptionAlgorithm: String

    public init(
        formatVersion: Int = 1,
        archiveID: UUID = UUID(),
        createdAt: Date = .now,
        appVersion: String = "0.1.0",
        letterCount: Int = 0,
        attachmentCount: Int = 0,
        recipientCount: Int = 0,
        encryptionAlgorithm: String = "AES-256-GCM"
    ) {
        self.formatVersion = formatVersion
        self.archiveID = archiveID
        self.createdAt = createdAt
        self.appVersion = appVersion
        self.letterCount = letterCount
        self.attachmentCount = attachmentCount
        self.recipientCount = recipientCount
        self.encryptionAlgorithm = encryptionAlgorithm
    }
}

// MARK: - Backup Payload

/// The complete set of archive data that the backup service serialises
/// and encrypts. The application layer populates this from the
/// persistent store before handing it to a provider.
public struct BackupPayload: Codable, Sendable {
    public var manifest: BackupManifest
    public var children: [ChildPayload]
    public var letters: [LetterPayload]
    public var attachments: [AttachmentPayload]
    public var branches: [BranchPayload]
    public var folders: [FolderPayload]
    public var members: [MemberPayload]
    public var invitations: [InvitationPayload]

    public init(
        manifest: BackupManifest = BackupManifest(),
        children: [ChildPayload] = [],
        letters: [LetterPayload] = [],
        attachments: [AttachmentPayload] = [],
        branches: [BranchPayload] = [],
        folders: [FolderPayload] = [],
        members: [MemberPayload] = [],
        invitations: [InvitationPayload] = []
    ) {
        self.manifest = manifest
        self.children = children
        self.letters = letters
        self.attachments = attachments
        self.branches = branches
        self.folders = folders
        self.members = members
        self.invitations = invitations
    }
}

// MARK: - Payload Primitives

public struct ChildPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var birthDate: Date?

    public init(id: UUID, name: String, birthDate: Date? = nil) {
        self.id = id
        self.name = name
        self.birthDate = birthDate
    }
}

public struct LetterPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var childID: UUID?
    public var branchID: UUID?
    public var folderID: UUID?
    public var authorMemberID: UUID?
    public var title: String
    public var body: String
    public var authorName: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sealedAt: Date?
    public var isFavorite: Bool
    public var unlockRuleRawValue: String
    public var unlockDate: Date?
    public var unlockAgeYearsValue: Int?
    public var lifeEventName: String
    public var manuallyReleasedAt: Date?

    public init(
        id: UUID,
        childID: UUID? = nil,
        branchID: UUID? = nil,
        folderID: UUID? = nil,
        authorMemberID: UUID? = nil,
        title: String,
        body: String,
        authorName: String,
        createdAt: Date,
        updatedAt: Date,
        sealedAt: Date? = nil,
        isFavorite: Bool = false,
        unlockRuleRawValue: String = "specificDate",
        unlockDate: Date? = nil,
        unlockAgeYearsValue: Int? = nil,
        lifeEventName: String = "",
        manuallyReleasedAt: Date? = nil
    ) {
        self.id = id
        self.childID = childID
        self.branchID = branchID
        self.folderID = folderID
        self.authorMemberID = authorMemberID
        self.title = title
        self.body = body
        self.authorName = authorName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sealedAt = sealedAt
        self.isFavorite = isFavorite
        self.unlockRuleRawValue = unlockRuleRawValue
        self.unlockDate = unlockDate
        self.unlockAgeYearsValue = unlockAgeYearsValue
        self.lifeEventName = lifeEventName
        self.manuallyReleasedAt = manuallyReleasedAt
    }
}

public struct AttachmentPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var letterID: UUID
    public var fileName: String
    public var contentTypeIdentifier: String
    public var kindRawValue: String
    public var createdAt: Date
    public var data: Data

    public init(
        id: UUID,
        letterID: UUID,
        fileName: String,
        contentTypeIdentifier: String,
        kindRawValue: String,
        createdAt: Date,
        data: Data
    ) {
        self.id = id
        self.letterID = letterID
        self.fileName = fileName
        self.contentTypeIdentifier = contentTypeIdentifier
        self.kindRawValue = kindRawValue
        self.createdAt = createdAt
        self.data = data
    }
}

public struct BranchPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kindRawValue: String
    public var parentBranchID: UUID?

    public init(
        id: UUID,
        name: String,
        kindRawValue: String,
        parentBranchID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.kindRawValue = kindRawValue
        self.parentBranchID = parentBranchID
    }
}

public struct FolderPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var branchID: UUID
    public var parentFolderID: UUID?
    public var name: String

    public init(
        id: UUID,
        branchID: UUID,
        parentFolderID: UUID? = nil,
        name: String
    ) {
        self.id = id
        self.branchID = branchID
        self.parentFolderID = parentFolderID
        self.name = name
    }
}

public struct MemberPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var relationship: String
    public var roleRawValue: String
    public var statusRawValue: String
    public var canInviteOthers: Bool

    public init(
        id: UUID,
        displayName: String,
        relationship: String,
        roleRawValue: String,
        statusRawValue: String = "active",
        canInviteOthers: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.relationship = relationship
        self.roleRawValue = roleRawValue
        self.statusRawValue = statusRawValue
        self.canInviteOthers = canInviteOthers
    }
}

public struct InvitationPayload: Codable, Equatable, Sendable {
    public var id: UUID
    public var inviteeDisplayName: String
    public var inviteeAddress: String
    public var relationship: String
    public var roleRawValue: String
    public var statusRawValue: String

    public init(
        id: UUID,
        inviteeDisplayName: String,
        inviteeAddress: String,
        relationship: String,
        roleRawValue: String,
        statusRawValue: String = "pending"
    ) {
        self.id = id
        self.inviteeDisplayName = inviteeDisplayName
        self.inviteeAddress = inviteeAddress
        self.relationship = relationship
        self.roleRawValue = roleRawValue
        self.statusRawValue = statusRawValue
    }
}

// MARK: - Backup Provider Protocol

/// An opaque handle returned after a provider successfully stores a
/// backup archive. The application layer persists this so it can
/// later delete or verify the remote copy.
public struct BackupRemoteHandle: Codable, Equatable, Sendable {
    public var identifier: String
    public var location: String
    public var metadata: [String: String]

    public init(
        identifier: String,
        location: String = "",
        metadata: [String: String] = [:]
    ) {
        self.identifier = identifier
        self.location = location
        self.metadata = metadata
    }
}

/// Errors that backup providers and the service may surface.
public enum BackupError: LocalizedError, Sendable {
    case notConfigured(BackupDestination)
    case encryptionFailed(String)
    case decryptionFailed(String)
    case serializationFailed(String)
    case providerError(BackupDestination, String)
    case insufficientSpace(Int64, Int64)
    case archiveCorrupted(String)
    case duplicatePrevention

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let d): "\(d.title) is not configured."
        case .encryptionFailed(let r): "Encryption failed: \(r)"
        case .decryptionFailed(let r): "Decryption failed: \(r)"
        case .serializationFailed(let r): "Serialization failed: \(r)"
        case .providerError(let d, let r): "\(d.title) error: \(r)"
        case .insufficientSpace(let need, let avail):
            "Insufficient space: need \(need) bytes, available \(avail) bytes."
        case .archiveCorrupted(let r): "Archive corrupted: \(r)"
        case .duplicatePrevention: "A backup with this identifier already exists."
        }
    }
}

/// Protocol that every storage backend implements. Providers are
/// instantiated by the application layer and registered with the
/// `BackupService`.
public protocol BackupProvider: Sendable {
    var destination: BackupDestination { get }

    /// Whether the provider has valid credentials and network access.
    func isReady() async -> Bool

    /// Store a serialised archive at the destination.
    /// - Parameter archive: The encrypted archive bytes.
    /// - Parameter manifest: Unencrypted metadata stored alongside.
    /// - Returns: A handle the caller can use to reference the remote copy.
    func store(
        archive: Data,
        manifest: BackupManifest
    ) async throws -> BackupRemoteHandle

    /// Retrieve an archive previously stored with this provider.
    func retrieve(
        handle: BackupRemoteHandle
    ) async throws -> Data

    /// List remote backup handles for this destination.
    func listRemoteBackups() async throws -> [BackupRemoteHandle]

    /// Remove a previously stored backup.
    func remove(handle: BackupRemoteHandle) async throws

    /// Available free space at the destination, in bytes, or nil
    /// if the provider does not report capacity.
    func availableSpace() async throws -> Int64?
}

// MARK: - Backup Service

/// Platform-agnostic backup orchestrator. The application layer
/// supplies one or more `BackupProvider` instances and a passphrase
/// resolver. The service handles encryption, serialisation,
/// retention, and error reporting.
public actor BackupService {
    private var providers: [BackupDestination: any BackupProvider] = [:]
    private let appVersion: String

    public init(appVersion: String = "0.1.0") {
        self.appVersion = appVersion
    }

    public func register(_ provider: any BackupProvider) {
        providers[provider.destination] = provider
    }

    public func provider(for destination: BackupDestination) -> (any BackupProvider)? {
        providers[destination]
    }

    /// Serialise a payload, encrypt it, and upload to the destination.
    /// The completion callback receives a `BackupRecord` suitable for
    /// local persistence.
    public func backup(
        payload: BackupPayload,
        to destination: BackupDestination,
        passphrase: String
    ) async throws -> BackupRecord {
        guard let provider = providers[destination] else {
            throw BackupError.notConfigured(destination)
        }
        guard try await provider.isReady() else {
            throw BackupError.providerError(destination, "Provider is not ready.")
        }

        var record = BackupRecord(
            destination: destination,
            status: .inProgress,
            letterCount: payload.letters.count,
            attachmentCount: payload.attachments.count
        )

        let manifest = BackupManifest(
            archiveID: record.id,
            createdAt: record.createdAt,
            appVersion: appVersion,
            letterCount: payload.letters.count,
            attachmentCount: payload.attachments.count,
            recipientCount: payload.children.count
        )

        var fullPayload = payload
        fullPayload.manifest = manifest

        // Serialise and encrypt.
        let archiveData: Data
        do {
            archiveData = try serializeAndEncrypt(payload: fullPayload, passphrase: passphrase)
        } catch {
            record.status = .failed
            record.errorMessage = error.localizedDescription
            throw error
        }

        // Check available space.
        if let available = try? await provider.availableSpace(),
           available < Int64(archiveData.count) {
            throw BackupError.insufficientSpace(Int64(archiveData.count), available)
        }

        // Store at destination.
        let handle: BackupRemoteHandle
        do {
            handle = try await provider.store(archive: archiveData, manifest: manifest)
        } catch {
            record.status = .failed
            record.errorMessage = error.localizedDescription
            throw BackupError.providerError(destination, error.localizedDescription)
        }

        record.status = .completed
        record.completedAt = .now
        record.sizeBytes = Int64(archiveData.count)
        record.remoteIdentifier = handle.identifier
        return record
    }

    /// Download, decrypt, and deserialise a backup from a remote handle.
    public func restore(
        from destination: BackupDestination,
        handle: BackupRemoteHandle,
        passphrase: String
    ) async throws -> BackupPayload {
        guard let provider = providers[destination] else {
            throw BackupError.notConfigured(destination)
        }
        guard try await provider.isReady() else {
            throw BackupError.providerError(destination, "Provider is not ready.")
        }

        let archiveData = try await provider.retrieve(handle: handle)
        return try decryptAndDeserialize(data: archiveData, passphrase: passphrase)
    }

    /// Enforce retention by removing the oldest backups beyond the
    /// configured count.
    public func enforceRetention(
        for destination: BackupDestination,
        maxCount: Int,
        existingRecords: [BackupRecord]
    ) async throws {
        guard let provider = providers[destination] else { return }

        let records = existingRecords
            .filter { $0.destination == destination && $0.status == .completed }
            .sorted { $0.createdAt < $1.createdAt }

        guard records.count > maxCount else { return }

        let toRemove = records.prefix(records.count - maxCount)
        let handles = try await provider.listRemoteBackups()

        for record in toRemove {
            if let remoteID = record.remoteIdentifier,
               let handle = handles.first(where: { $0.identifier == remoteID }) {
                try? await provider.remove(handle: handle)
            }
        }
    }

    /// Remove a single backup from the remote destination.
    public func removeBackup(
        from destination: BackupDestination,
        remoteIdentifier: String
    ) async throws {
        guard let provider = providers[destination] else {
            throw BackupError.notConfigured(destination)
        }
        let handles = try await provider.listRemoteBackups()
        guard let handle = handles.first(where: { $0.identifier == remoteIdentifier }) else {
            throw BackupError.providerError(destination, "Backup not found.")
        }
        try await provider.remove(handle: handle)
    }
}

// MARK: - Crypto Helpers

import CryptoKit

extension BackupService {
    private func serializeAndEncrypt(
        payload: BackupPayload,
        passphrase: String
    ) throws -> Data {
        let jsonData = try JSONEncoder().encode(payload)

        guard let keyData = passphrase.data(using: .utf8) else {
            throw BackupError.encryptionFailed("Invalid passphrase encoding.")
        }

        let key = SymmetricKey(data: SHA256.hash(data: keyData))
        let sealed = try AES.GCM.seal(jsonData, using: key)
        guard let combined = sealed.combined else {
            throw BackupError.encryptionFailed("Failed to produce combined ciphertext.")
        }

        return combined
    }

    private func decryptAndDeserialize(
        data: Data,
        passphrase: String
    ) throws -> BackupPayload {
        guard let keyData = passphrase.data(using: .utf8) else {
            throw BackupError.decryptionFailed("Invalid passphrase encoding.")
        }

        let key = SymmetricKey(data: SHA256.hash(data: keyData))

        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.SealedBox(combined: data)
        } catch {
            throw BackupError.archiveCorrupted("Invalid ciphertext format.")
        }

        let decrypted: Data
        do {
            decrypted = try AES.GCM.open(sealed, using: key)
        } catch CryptoKitError.authenticationFailure {
            throw BackupError.decryptionFailed("Wrong passphrase or corrupted archive.")
        } catch {
            throw BackupError.decryptionFailed(error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(BackupPayload.self, from: decrypted)
        } catch {
            throw BackupError.archiveCorrupted("Payload deserialization failed: \(error.localizedDescription)")
        }
    }
}

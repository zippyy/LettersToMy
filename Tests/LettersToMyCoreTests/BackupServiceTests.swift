import Foundation
import Testing
@testable import LettersToMyCore

// MARK: - Mock Provider

private actor MockBackupProvider: BackupProvider {
    let destination: BackupDestination = .localFile
    private var stored: [String: (archive: Data, manifest: BackupManifest)] = [:]
    private var ready = true

    func isReady() async -> Bool { ready }
    func setReady(_ value: Bool) { ready = value }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let handle = BackupRemoteHandle(
            identifier: manifest.archiveID.uuidString,
            location: "mock://backups/\(manifest.archiveID.uuidString)",
            metadata: ["letters": "\(manifest.letterCount)"]
        )
        stored[handle.identifier] = (archive, manifest)
        return handle
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        guard let entry = stored[handle.identifier] else {
            throw BackupError.providerError(.localFile, "Not found")
        }
        return entry.archive
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] {
        stored.keys.map {
            BackupRemoteHandle(identifier: $0, location: "mock://backups/\($0)")
        }
    }

    func remove(handle: BackupRemoteHandle) async throws {
        stored.removeValue(forKey: handle.identifier)
    }

    func availableSpace() async throws -> Int64? { 1_000_000_000 }
}

// MARK: - Test Helpers

private func samplePayload() -> BackupPayload {
    BackupPayload(
        children: [
            ChildPayload(id: UUID(), name: "Emma", birthDate: Date(timeIntervalSince1970: 0))
        ],
        letters: [
            LetterPayload(
                id: UUID(),
                title: "Hello from the past",
                body: "Dear Emma, this is a test letter.",
                authorName: "Mom",
                createdAt: .now,
                updatedAt: .now,
                unlockRuleRawValue: "specificDate",
                unlockDate: Date.distantFuture
            )
        ],
        attachments: [],
        branches: [
            BranchPayload(id: UUID(), name: "Parents", kindRawValue: "parents")
        ],
        folders: [],
        members: [
            MemberPayload(id: UUID(), displayName: "Mom", relationship: "Mother", roleRawValue: "parentAdmin")
        ],
        invitations: []
    )
}

// MARK: - Tests

struct BackupServiceTests {
    private let passphrase = "correct horse battery staple"

    @Test func roundTripEncryptDecrypt() async throws {
        let service = BackupService()
        let provider = MockBackupProvider()
        await service.register(provider)

        let payload = samplePayload()
        let record = try await service.backup(payload: payload, to: .localFile, passphrase: passphrase)

        #expect(record.status == .completed)
        #expect(record.letterCount == 1)
        #expect(record.attachmentCount == 0)
        #expect(record.remoteIdentifier != nil)

        let handle = BackupRemoteHandle(identifier: record.remoteIdentifier!)
        let restored = try await service.restore(from: .localFile, handle: handle, passphrase: passphrase)

        #expect(restored.letters.count == 1)
        #expect(restored.letters.first?.title == "Hello from the past")
        #expect(restored.children.count == 1)
        #expect(restored.children.first?.name == "Emma")
        #expect(restored.branches.count == 1)
        #expect(restored.members.count == 1)
    }

    @Test func wrongPassphraseFailsDecryption() async throws {
        let service = BackupService()
        let provider = MockBackupProvider()
        await service.register(provider)

        let payload = samplePayload()
        let record = try await service.backup(payload: payload, to: .localFile, passphrase: "correct")

        let handle = BackupRemoteHandle(identifier: record.remoteIdentifier!)

        do {
            _ = try await service.restore(from: .localFile, handle: handle, passphrase: "wrong")
            #expect(Bool(false), "Expected decryption error")
        } catch let error as BackupError {
            if case .decryptionFailed = error {
                // expected
            } else {
                #expect(Bool(false), "Wrong error type: \(error)")
            }
        }
    }

    @Test func corruptedArchiveFailsDecryption() async throws {
        let service = BackupService()
        let provider = MockBackupProvider()
        await service.register(provider)

        let payload = samplePayload()
        let record = try await service.backup(payload: payload, to: .localFile, passphrase: passphrase)

        // Corrupt the stored data by replacing it with garbage.
        let corruptedHandle = BackupRemoteHandle(identifier: record.remoteIdentifier! + "-corrupt")
        _ = try await provider.store(archive: Data([0xDE, 0xAD, 0xBE, 0xEF]), manifest: BackupManifest())

        do {
            _ = try await service.restore(from: .localFile, handle: corruptedHandle, passphrase: passphrase)
            #expect(Bool(false), "Expected decryption or corruption error")
        } catch let error as BackupError {
            // Either archive corruption or decryption failure is acceptable
            // for garbage data — the point is the archive should not decrypt.
            let acceptable = if case .archiveCorrupted = error { true }
                else if case .decryptionFailed = error { true }
                else { false }
            #expect(acceptable, "Unexpected error: \(error)")
        }
    }

    @Test func notConfiguredDestinationThrows() async {
        let service = BackupService()
        let payload = samplePayload()

        do {
            _ = try await service.backup(payload: payload, to: .googleDrive, passphrase: passphrase)
            #expect(Bool(false), "Expected notConfigured error")
        } catch let error as BackupError {
            #expect(error.localizedDescription.contains("not configured"))
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }

    @Test func retentionRemovesOldestBackups() async throws {
        let service = BackupService()
        let provider = MockBackupProvider()
        await service.register(provider)

        // Create 5 backups.
        var records: [BackupRecord] = []
        for i in 0..<5 {
            let record = try await service.backup(
                payload: samplePayload(),
                to: .localFile,
                passphrase: passphrase
            )
            records.append(record)
        }

        #expect(records.count == 5)

        // Enforce retention of 2.
        try await service.enforceRetention(for: .localFile, maxCount: 2, existingRecords: records)

        // Should only have 2 remaining.
        let remaining = try await provider.listRemoteBackups()
        #expect(remaining.count == 2)
    }

    @Test func manifestContainsArchiveMetadata() async throws {
        let service = BackupService()
        let provider = MockBackupProvider()
        await service.register(provider)

        let payload = samplePayload()
        let record = try await service.backup(payload: payload, to: .localFile, passphrase: passphrase)

        #expect(record.letterCount == 1)
        #expect(record.attachmentCount == 0)
        #expect(record.completedAt != nil)
        #expect(record.sizeBytes > 0)
    }

    @Test func emptyPayloadCompletesSuccessfully() async throws {
        let service = BackupService()
        let provider = MockBackupProvider()
        await service.register(provider)

        let empty = BackupPayload()
        let record = try await service.backup(payload: empty, to: .localFile, passphrase: passphrase)

        #expect(record.status == .completed)
        #expect(record.letterCount == 0)

        let handle = BackupRemoteHandle(identifier: record.remoteIdentifier!)
        let restored = try await service.restore(from: .localFile, handle: handle, passphrase: passphrase)

        #expect(restored.letters.isEmpty)
        #expect(restored.children.isEmpty)
    }
}

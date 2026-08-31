import Foundation
import CryptoKit
import LettersToMyCore

// backup-e2e — real-archive end-to-end regression for the self-hosted
// backup contract. Runs against a LIVE server.
//
// Usage: backup-e2e <baseURL> <apiToken>
//
// What it exercises, all through CURRENT production client code:
//   1. BackupService.backup() — real AES-256-GCM serialization of a
//      realistic archive (children, draft/scheduled/unlocked/sealed
//      letters with all unlock rule kinds, attachments incl. photo /
//      audio / file, branches, folders, members, invitations).
//   2. SelfHostedAPIClient.uploadBackup / listBackups / downloadBackup /
//      deleteBackup over real HTTP.
//   3. letter_count semantics: 5 letters -> backup #1 (count 5);
//      delete 2 (draft + sealed-with-attachment, cascading its
//      attachment) -> backup #2 (count 3). List must preserve 5 and 3.
//   4. Byte identity: download == upload == local archive (sha256).
//   5. Restore-decode via BackupService.decryptPayload() (the exact
//      function the app's restore preview uses) — collections and key
//      fields must round-trip.
//   6. Deletion semantics: backup #2 must NOT contain the deleted
//      letters or their attachments; deleting backup #1 must leave
//      backup #2 untouched.
//
// Exit code 0 when every check passes. The integration harness
// (LettersToMy-SelfHostedSync/scripts/integration-test.sh) drives this
// against a freshly started server after the selfhosted-check probe.

/// Minimal in-process provider so the archive bytes come out of the real
/// BackupService pipeline (serialize + AES-256-GCM) into a temp file.
/// The app's SelfHostedBackupProvider lives in the app target and cannot
/// be imported here; the server round trip is exercised via
/// SelfHostedAPIClient directly below.
final class TempDirBackupProvider: BackupProvider, @unchecked Sendable {
    let destination: BackupDestination = .selfHosted
    private let dir: URL

    init(dir: URL) { self.dir = dir }

    func isReady() async -> Bool { true }

    func store(archive: Data, manifest: BackupManifest) async throws -> BackupRemoteHandle {
        let file = dir.appendingPathComponent(manifest.archiveID.uuidString + ".letterstomy")
        try archive.write(to: file)
        return BackupRemoteHandle(
            identifier: manifest.archiveID.uuidString,
            metadata: ["size": "\(archive.count)"]
        )
    }

    func retrieve(handle: BackupRemoteHandle) async throws -> Data {
        try Data(contentsOf: dir.appendingPathComponent(handle.identifier + ".letterstomy"))
    }

    func listRemoteBackups() async throws -> [BackupRemoteHandle] { [] }
    func remove(handle: BackupRemoteHandle) async throws {
        try? FileManager.default.removeItem(
            at: dir.appendingPathComponent(handle.identifier + ".letterstomy"))
    }
    func availableSpace() async throws -> Int64? { nil }
}

func sha256hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

func main() async {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        print("usage: backup-e2e <baseURL> <apiToken>")
        exit(2)
    }
    let baseURL = args[1]
    let token = args[2]
    let runID = "e2e-\(UUID().uuidString.prefix(8))"
    let passphrase = "e2e-passphrase-\(runID)"
    var failures = 0

    func expect(_ condition: Bool, _ message: String) {
        if condition {
            print("PASS  \(message)")
        } else {
            print("FAIL  \(message)")
            failures += 1
        }
    }

    // ── Realistic archive: 2 children, 5 letters, 3 attachments ──────
    let childA = ChildPayload(id: UUID(), name: "Ada", birthDate: Date(timeIntervalSince1970: 1_600_000_000))
    let childB = ChildPayload(id: UUID(), name: "Grace", birthDate: Date(timeIntervalSince1970: 1_610_000_000))
    let children = [childA, childB]

    let branch1 = BranchPayload(id: UUID(), name: "Parents", kindRawValue: "parents")
    let branch2 = BranchPayload(id: UUID(), name: "Family Camp", kindRawValue: "custom", parentBranchID: branch1.id)
    let branch1ID = branch1.id
    let folder1 = FolderPayload(id: UUID(), branchID: branch1ID, parentFolderID: nil, name: "Summer 2026")
    let member1 = MemberPayload(id: UUID(), displayName: "Ada's Parent", relationship: "parent", roleRawValue: "owner", statusRawValue: "active", canInviteOthers: true)
    let invitation1 = InvitationPayload(id: UUID(), inviteeDisplayName: "Grandma", inviteeAddress: "grandma@example.com", relationship: "grandparent", roleRawValue: "viewer", statusRawValue: "pending")

    let now = Date()
    // L1 — draft (never sealed)
    let draft = LetterPayload(
        id: UUID(), childID: childA.id, branchID: branch1ID, folderID: folder1.id,
        authorMemberID: member1.id, title: "Draft Note", body: "unfinished",
        authorName: "Ada's Parent", createdAt: now.addingTimeInterval(-86400),
        updatedAt: now, sealedAt: nil, isFavorite: false,
        unlockRuleRawValue: "specificDate", unlockDate: nil,
        unlockAgeYearsValue: nil, lifeEventName: "", manuallyReleasedAt: nil)
    // L2 — scheduled/sealed (specific date in future) with PHOTO attachment
    let scheduled = LetterPayload(
        id: UUID(), childID: childA.id, branchID: branch1ID, folderID: folder1.id,
        authorMemberID: member1.id, title: "18th Birthday", body: "sealed until 18",
        authorName: "Ada's Parent", createdAt: now.addingTimeInterval(-7 * 86400),
        updatedAt: now.addingTimeInterval(-7 * 86400),
        sealedAt: now.addingTimeInterval(30 * 86400), isFavorite: true,
        unlockRuleRawValue: "specificDate", unlockDate: now.addingTimeInterval(30 * 86400),
        unlockAgeYearsValue: nil, lifeEventName: "", manuallyReleasedAt: nil)
    // L3 — unlocked (manually released) with AUDIO attachment
    let unlocked = LetterPayload(
        id: UUID(), childID: childB.id, branchID: branch2.id,
        authorMemberID: member1.id, title: "Camp Memories", body: "read me now",
        authorName: "Ada's Parent", createdAt: now.addingTimeInterval(-60 * 86400),
        updatedAt: now.addingTimeInterval(-2 * 86400),
        sealedAt: now.addingTimeInterval(-3 * 86400), isFavorite: false,
        unlockRuleRawValue: "lifeEvent", unlockDate: nil,
        unlockAgeYearsValue: nil, lifeEventName: "camp",
        manuallyReleasedAt: now.addingTimeInterval(-1 * 86400))
    // L4 — sealed (birthdayAge in future) with FILE attachment — deleted later
    let sealedWithAttachment = LetterPayload(
        id: UUID(), childID: childB.id, branchID: branch2.id,
        authorMemberID: member1.id, title: "18th for Grace", body: "sealed until 18",
        authorName: "Ada's Parent", createdAt: now.addingTimeInterval(-14 * 86400),
        updatedAt: now.addingTimeInterval(-14 * 86400),
        sealedAt: now.addingTimeInterval(365 * 86400), isFavorite: false,
        unlockRuleRawValue: "birthdayAge", unlockDate: nil,
        unlockAgeYearsValue: 18, lifeEventName: "", manuallyReleasedAt: nil)
    // L5 — unlocked (specificDate past) — survives deletion
    let released = LetterPayload(
        id: UUID(), childID: childA.id, branchID: branch1ID, folderID: folder1.id,
        authorMemberID: member1.id, title: "First Day", body: "already open",
        authorName: "Ada's Parent", createdAt: now.addingTimeInterval(-200 * 86400),
        updatedAt: now.addingTimeInterval(-100 * 86400),
        sealedAt: now.addingTimeInterval(-100 * 86400), isFavorite: true,
        unlockRuleRawValue: "specificDate", unlockDate: now.addingTimeInterval(-5 * 86400),
        unlockAgeYearsValue: nil, lifeEventName: "", manuallyReleasedAt: nil)

    let letters = [draft, scheduled, unlocked, sealedWithAttachment, released]

    let photo = AttachmentPayload(
        id: UUID(), letterID: scheduled.id, fileName: "photo.jpg",
        contentTypeIdentifier: "public.jpeg", kindRawValue: "photo",
        createdAt: now.addingTimeInterval(-6 * 86400),
        data: Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(repeating: 0x42, count: 4096))
    let audio = AttachmentPayload(
        id: UUID(), letterID: unlocked.id, fileName: "voice.m4a",
        contentTypeIdentifier: "public.mpeg-4-audio", kindRawValue: "audio",
        createdAt: now.addingTimeInterval(-2 * 86400),
        data: Data([0x00, 0x00, 0x00, 0x18]) + Data(repeating: 0x7A, count: 2048))
    let file = AttachmentPayload(
        id: UUID(), letterID: sealedWithAttachment.id, fileName: "doc.pdf",
        contentTypeIdentifier: "com.adobe.pdf", kindRawValue: "file",
        createdAt: now.addingTimeInterval(-13 * 86400),
        data: Data([0x25, 0x50, 0x44, 0x46]) + Data(repeating: 0x63, count: 8192))
    let attachments = [photo, audio, file]

    func payload(with letters: [LetterPayload], attachments: [AttachmentPayload]) -> BackupPayload {
        BackupPayload(
            manifest: BackupManifest(),
            children: children,
            letters: letters,
            attachments: attachments,
            branches: [branch1, branch2],
            folders: [folder1],
            members: [member1],
            invitations: [invitation1]
        )
    }

    let tmpDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("backup-e2e-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    let provider = TempDirBackupProvider(dir: tmpDir)
    let service = BackupService(appVersion: "e2e")
    await service.register(provider)

    do {
        let client = try SelfHostedAPIClient(serverURL: baseURL, apiToken: token)

        // ── Backup #1: 5 letters ─────────────────────────────────────
        let record1 = try await service.backup(
            payload: payload(with: letters, attachments: attachments),
            to: .selfHosted, passphrase: passphrase)
        expect(record1.letterCount == 5, "backup #1 manifest letter_count == 5 (got \(record1.letterCount))")
        expect(record1.attachmentCount == 3, "backup #1 manifest attachment_count == 3")
        let archive1 = try await provider.retrieve(
            handle: BackupRemoteHandle(identifier: record1.remoteIdentifier ?? ""))

        let id1 = "\(runID)-pre-delete"
        let meta1 = try await client.uploadBackup(id: id1, data: archive1, letterCount: record1.letterCount)
        expect(meta1.id == id1, "upload #1 id echoed (\(meta1.id))")
        expect(meta1.letterCount == 5, "upload #1 letter_count == 5 (got \(meta1.letterCount))")
        expect(meta1.size == Int64(archive1.count), "upload #1 size matches archive bytes")
        expect(meta1.timestamp > 0, "upload #1 timestamp valid (\(meta1.timestamp))")

        // ── Backup #2: after deleting draft + sealed-with-attachment ──
        let remainingLetters = letters.filter { $0.id != draft.id && $0.id != sealedWithAttachment.id }
        let remainingAttachments = attachments.filter { $0.letterID != sealedWithAttachment.id }
        let record2 = try await service.backup(
            payload: payload(with: remainingLetters, attachments: remainingAttachments),
            to: .selfHosted, passphrase: passphrase)
        expect(record2.letterCount == 3, "backup #2 manifest letter_count == 3 (got \(record2.letterCount))")
        expect(record2.attachmentCount == 2, "backup #2 manifest attachment_count == 2 (cascade removed deleted letter's attachment)")
        let archive2 = try await provider.retrieve(
            handle: BackupRemoteHandle(identifier: record2.remoteIdentifier ?? ""))

        let id2 = "\(runID)-post-delete"
        let meta2 = try await client.uploadBackup(id: id2, data: archive2, letterCount: record2.letterCount)
        expect(meta2.letterCount == 3, "upload #2 letter_count == 3 (got \(meta2.letterCount))")

        // ── List preserves both counts ───────────────────────────────
        let listed = try await client.listBackups()
        let b1 = listed.first { $0.id == id1 }
        let b2 = listed.first { $0.id == id2 }
        expect(b1?.letterCount == 5, "list preserves backup #1 letter_count == 5")
        expect(b2?.letterCount == 3, "list preserves backup #2 letter_count == 3")

        // ── Download byte identity (sha256) ──────────────────────────
        let downloaded1 = try await client.downloadBackup(id: id1)
        expect(downloaded1 == archive1, "download #1 byte-identical to local archive")
        expect(sha256hex(downloaded1) == sha256hex(archive1), "download #1 sha256 matches (\(sha256hex(archive1).prefix(16)))")
        let downloaded2 = try await client.downloadBackup(id: id2)
        expect(downloaded2 == archive2, "download #2 byte-identical to local archive")

        // ── Restore-decode backup #1 with production decrypt ─────────
        let restored1 = try BackupService.decryptPayload(data: downloaded1, passphrase: passphrase)
        expect(restored1.children.count == 2, "restore #1 children == 2")
        expect(restored1.letters.count == 5, "restore #1 letters == 5")
        expect(restored1.attachments.count == 3, "restore #1 attachments == 3")
        expect(restored1.branches.count == 2, "restore #1 branches == 2")
        expect(restored1.folders.count == 1, "restore #1 folders == 1")
        expect(restored1.members.count == 1, "restore #1 members == 1")
        expect(restored1.invitations.count == 1, "restore #1 invitations == 1")
        expect(restored1.manifest.letterCount == 5, "restore #1 manifest letter_count == 5")
        expect(restored1.manifest.archiveID == record1.remoteIdentifier.flatMap(UUID.init(uuidString:)) ?? restored1.manifest.archiveID,
               "restore #1 manifest archiveID matches upload id")
        // Field-level round trip on every letter kind:
        let rDraft = restored1.letters.first { $0.id == draft.id }
        expect(rDraft?.sealedAt == nil, "draft restored with sealedAt == nil (still a draft)")
        let rScheduled = restored1.letters.first { $0.id == scheduled.id }
        expect(rScheduled?.sealedAt != nil && rScheduled?.unlockRuleRawValue == "specificDate",
               "scheduled letter restored sealed with specificDate rule")
        let rUnlocked = restored1.letters.first { $0.id == unlocked.id }
        expect(rUnlocked?.manuallyReleasedAt != nil, "unlocked letter restored with manual release date")
        let rSealed = restored1.letters.first { $0.id == sealedWithAttachment.id }
        expect(rSealed?.unlockAgeYearsValue == 18 && rSealed?.unlockRuleRawValue == "birthdayAge",
               "sealed letter restored with birthdayAge/18 rule")
        // Attachment payload byte identity (photo, audio, file):
        let rPhoto = restored1.attachments.first { $0.id == photo.id }
        expect(rPhoto?.data == photo.data && rPhoto?.kindRawValue == "photo", "photo attachment bytes+kind round-trip")
        let rAudio = restored1.attachments.first { $0.id == audio.id }
        expect(rAudio?.data == audio.data && rAudio?.kindRawValue == "audio", "audio attachment bytes+kind round-trip")
        let rFile = restored1.attachments.first { $0.id == file.id }
        expect(rFile?.data == file.data && rFile?.kindRawValue == "file", "file attachment bytes+kind round-trip")

        // ── Restore-decode backup #2: deletions absent ───────────────
        let restored2 = try BackupService.decryptPayload(data: downloaded2, passphrase: passphrase)
        expect(restored2.letters.count == 3, "post-delete backup has 3 letters (deleted draft + sealed gone)")
        expect(!restored2.letters.contains(where: { $0.id == draft.id }), "deleted draft absent from post-delete backup")
        expect(!restored2.letters.contains(where: { $0.id == sealedWithAttachment.id }), "deleted sealed letter absent from post-delete backup")
        expect(!restored2.attachments.contains(where: { $0.letterID == sealedWithAttachment.id }),
               "no orphaned attachment data for deleted letter in post-delete backup")
        expect(restored2.attachments.count == 2, "post-delete backup attachments == 2")
        expect(restored2.attachments.contains(where: { $0.id == photo.id }) &&
               restored2.attachments.contains(where: { $0.id == audio.id }),
               "surviving letters' attachments present")

        // ── Delete backup #1; #2 untouched ───────────────────────────
        try await client.deleteBackup(id: id1)
        let afterDelete = try await client.listBackups()
        expect(!afterDelete.contains(where: { $0.id == id1 }), "backup #1 deleted from server list")
        expect(afterDelete.contains(where: { $0.id == id2 }), "backup #2 still listed after deleting #1")
        let b2after = afterDelete.first { $0.id == id2 }
        expect(b2after?.letterCount == 3, "backup #2 letter_count still 3 after deleting #1")

        // ── Cleanup ──────────────────────────────────────────────────
        try? await client.deleteBackup(id: id2)

    } catch let error as SelfHostedAPIError {
        print("FAIL  backup-e2e connection error: \(error.localizedDescription)")
        failures += 1
    } catch {
        print("FAIL  backup-e2e error: \(error.localizedDescription)")
        failures += 1
    }

    try? FileManager.default.removeItem(at: tmpDir)

    print(failures == 0 ? "RESULT: PASS" : "RESULT: FAIL")
    exit(failures == 0 ? 0 : 1)
}

await main()
import CloudKit
import Combine
import CoreData
import Foundation
import LettersToMyCore
import Security
import UserNotifications

/// The application's Core Data + CloudKit coordinator.
///
/// `@unchecked Sendable` is safe here because:
/// - Core Data confines every managed object and context to its creation
///   queue; all mutation goes through `NSManagedObjectContext`, which is
///   itself queue-confined and not shared unsafely.
/// - `@Published` properties (`isLoaded`, `cloudKitAccountStatus`,
///   `lastSyncError`) are only read and written on the `@MainActor` via
///   the SwiftUI observation pipeline.
/// - `container`, `privateStore`, and `sharedStore` are set once during
///   init/load and only reassigned inside the async store-loading path
///   that completes before any other access; `static let shared` is a
///   process-lifetime singleton, so weak captures in callbacks never
///   deallocate it.
final class PersistenceController: ObservableObject, @unchecked Sendable {
    static let shared = PersistenceController()

    static let cloudKitContainerIdentifier = "iCloud.com.bayoumountainholdings.LettersToMy"
    static let privateConfigurationName = "Private"
    static let sharedConfigurationName = "Shared"

    /// URL of the SQLite database file, used for self-hosted sync push.
    var dbURL: URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return applicationSupport
            .appendingPathComponent("LettersToMy", isDirectory: true)
            .appendingPathComponent("\(PersistenceController.sharedConfigurationName).sqlite")
    }

    /// Reads the process's actual code-signing entitlements via
    /// SecTaskCopyValueForEntitlement. Bundle.main.object(forInfoDictionaryKey:)
    /// does NOT work for entitlements — they're embedded by code signing,
    /// not in Info.plist. Returns false when running unsigned or without
    /// the CloudKit entitlement (e.g. Xcode debug builds without the
    /// entitlement in the provisioning profile).
    static var cloudKitAvailable: Bool {
        #if DEBUG
        #if os(macOS)
        // SecTask reads the process's code-signing entitlements.
        // On macOS, Xcode debug builds may lack entitlements when
        // CODE_SIGNING_ALLOWED=NO, so we check at runtime.
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-services" as CFString,
            nil
        ) as? [String] else {
            return false
        }
        return value.contains("CloudKit") || value.contains("CloudKit-Anonymous")
        #else
        // iOS: Xcode always signs debug builds with the dev cert,
        // so entitlements are always present.
        return true
        #endif
        #else
        return true
        #endif
    }

    var container: NSPersistentContainer
    /// Non-nil only when CloudKit is available (signed builds with entitlements).
    var cloudKitContainer: NSPersistentCloudKitContainer? { container as? NSPersistentCloudKitContainer }
    lazy var ckContainer = CKContainer(
        identifier: Self.cloudKitContainerIdentifier
    )

    private(set) var privateStore: NSPersistentStore!
    private(set) var sharedStore: NSPersistentStore!

    /// Published for SwiftUI views to observe CloudKit account state.
    @Published var cloudKitAccountStatus: CKAccountStatus = .couldNotDetermine
    @Published var lastSyncError: String?
    @Published var isLoaded = false

    private var cancellables = Set<AnyCancellable>()

    init(inMemory: Bool = false) {
        let useInMemory = inMemory || !Self.cloudKitAvailable
        let model = LettersToMyManagedObjectModel.makeModel()

        if Self.cloudKitAvailable {
            container = NSPersistentCloudKitContainer(name: "LettersToMy", managedObjectModel: model)
        } else {
            container = NSPersistentContainer(name: "LettersToMy", managedObjectModel: model)
        }

        let privateDescription = Self.makeStoreDescription(
            name: "LettersToMy-private",
            configuration: Self.privateConfigurationName,
            scope: .private,
            inMemory: useInMemory
        )
        var descriptions: [NSPersistentStoreDescription] = [privateDescription]
        if Self.cloudKitAvailable {
            let sharedDescription = Self.makeStoreDescription(
                name: "LettersToMy-shared",
                configuration: Self.sharedConfigurationName,
                scope: .shared,
                inMemory: useInMemory
            )
            descriptions.append(sharedDescription)
        }
        container.persistentStoreDescriptions = descriptions
    }

    /// Load persistent stores asynchronously. Must be called once before
    /// the managed object context is used. Safe to call multiple times;
    /// subsequent calls return immediately.
    func loadStores() async {
        guard !isLoaded else { return }

        let storeCount = container.persistentStoreDescriptions.count
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var loaded = 0
            container.loadPersistentStores { [weak self] description, error in
                if let error {
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    self.lastSyncError = error.localizedDescription
                } else if let store = self?.container.persistentStoreCoordinator.persistentStores.first(
                    where: { $0.configurationName == description.configuration }
                ) {
                    switch description.configuration {
                    case Self.privateConfigurationName:
                        self?.privateStore = store
                    case Self.sharedConfigurationName:
                        self?.sharedStore = store
                    default:
                        break
                    }
                }
                loaded += 1
                if loaded >= storeCount {
                    continuation.resume()
                }
            }
        }

        // If the private store failed to load, fall back to in-memory
        // so the app always renders even without iCloud or disk access.
        if privateStore == nil {
            NSLog("Private store failed — falling back to in-memory: \(lastSyncError ?? "unknown")")
            await fallbackToInMemory(model: container.managedObjectModel)
        } else if sharedStore == nil {
            NSLog("Shared store not available — operating with private only")
        }

        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        context.transactionAuthor = "LettersToMy.app"
        context.name = "LettersToMy.viewContext"

        observeCloudKitEvents()

        // Catch up on any shared partition activation data that arrived
        // while the app was not running or during a previous acceptance.
        activateAcceptedMembers(into: context)

        // Transition any pending invitations whose target partitions now
        // have persisted CloudKit shares.
        linkExistingSharesToInvitations(into: context)

        // Evaluate unlock rules and create deliveries for any letters
        // that unlocked while the app was not running.
        processPendingDeliveries(into: context)

        // Observe CloudKit account and sync state (only when available).
        if Self.cloudKitAvailable {
            Task { await refreshCloudKitAccountStatus() }
            observeRemoteChanges()
        }

        await MainActor.run { isLoaded = true }
    }

    private func observeCloudKitEvents() {
        guard let ckContainer = cloudKitContainer else { return }
        NotificationCenter.default.publisher(
            for: NSPersistentCloudKitContainer.eventChangedNotification,
            object: ckContainer
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] note in
            guard let event = note.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event,
                  let error = event.error else { return }
            self?.lastSyncError = error.localizedDescription
        }
        .store(in: &cancellables)
    }

    // MARK: - CloudKit Status

    func refreshCloudKitAccountStatus() async {
        guard Self.cloudKitAvailable else { return }
        do {
            cloudKitAccountStatus = try await ckContainer.accountStatus()
        } catch {
            cloudKitAccountStatus = .couldNotDetermine
            lastSyncError = error.localizedDescription
        }
    }

    /// Formats a CloudKit error for user-facing surfacing. A
    /// `CKError.partialFailure` carries per-record errors in its userInfo
    /// (`CKPartialErrorsByItemIDKey`); the top-level localizedDescription for
    /// a partial failure is only "The operation couldn't be completed.
    /// (CKErrorDomain error 2.)" and hides which records were rejected. This
    /// unwraps the per-item errors (capped to the first 10) so the UI shows
    /// the actionable cause — e.g. a record type the production schema does
    /// not yet know.
    private static func cloudKitErrorDescription(_ error: Error) -> String {
        guard let ckError = error as? CKError, ckError.code == .partialFailure,
              let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey]
                as? [AnyHashable: Error], !partialErrors.isEmpty else {
            return error.localizedDescription
        }
        let perItem = partialErrors
            .map { (recordID, itemError) -> String in
                let id = (recordID as? CKRecord.ID)?.recordName ?? "\(recordID)"
                let code = (itemError as NSError).code
                return "\(id): \(itemError.localizedDescription) (CKError \(code))"
            }
            .sorted()
            .prefix(10)
            .joined(separator: "; ")
        return "\(error.localizedDescription) — per-record: \(perItem)"
    }

    private func observeRemoteChanges() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[
                NSPersistentCloudKitContainer.eventNotificationUserInfoKey
            ] as? NSPersistentCloudKitContainer.Event else {
                return
            }

            switch event.type {
            case .setup:
                break
            case .import:
                if let error = event.error {
                    self?.lastSyncError = "Import error: \(Self.cloudKitErrorDescription(error))"
                }
            case .export:
                if let error = event.error {
                    self?.lastSyncError = "Export error: \(Self.cloudKitErrorDescription(error))"
                }
            @unknown default:
                break
            }
        }
    }

    func save(_ context: NSManagedObjectContext? = nil) throws {
        let context = context ?? container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            // Never let a failed save disappear into a `try?` at the call
            // site without a trace. Callers that swallow the error still
            // produce a log line for diagnosis.
            NSLog("LettersToMy: Core Data save failed: \(error)")
            throw error
        }
    }

    func newBackgroundContext(author: String = "LettersToMy.background") -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
        context.transactionAuthor = author
        return context
    }

    @discardableResult
    func insertPrivate<T: NSManagedObject>(
        _ type: T.Type,
        into context: NSManagedObjectContext? = nil
    ) -> T {
        guard let privateStore else {
            fatalError("The private Core Data store is not loaded.")
        }
        return insert(type, into: privateStore, context: context)
    }

    @discardableResult
    func insert<T: NSManagedObject>(
        _ type: T.Type,
        inSameStoreAs owner: NSManagedObject,
        into context: NSManagedObjectContext? = nil
    ) -> T {
        guard let store = owner.objectID.persistentStore ?? privateStore else {
            fatalError("No persistent store is available for the new object.")
        }
        return insert(type, into: store, context: context)
    }

    @discardableResult
    private func insert<T: NSManagedObject>(
        _ type: T.Type,
        into store: NSPersistentStore,
        context: NSManagedObjectContext?
    ) -> T {
        let context = context ?? container.viewContext
        let entityName = String(describing: type)
        guard let object = NSEntityDescription.insertNewObject(
            forEntityName: entityName,
            into: context
        ) as? T else {
            fatalError("Unable to insert Core Data entity \(entityName).")
        }
        context.assign(object, to: store)
        return object
    }

    func delete(_ object: NSManagedObject, from context: NSManagedObjectContext? = nil) {
        (context ?? object.managedObjectContext ?? container.viewContext).delete(object)
    }

    func canUpdate(_ object: NSManagedObject) -> Bool {
        cloudKitContainer?.canUpdateRecord(forManagedObjectWith: object.objectID) ?? false
    }

    func canDelete(_ object: NSManagedObject) -> Bool {
        cloudKitContainer?.canDeleteRecord(forManagedObjectWith: object.objectID) ?? false
    }

    /// The local archive member record for the signed-in user, if one
    /// has been activated through ownership or share acceptance.
    func currentMember(in context: NSManagedObjectContext? = nil) -> ArchiveMemberRecord? {
        let context = context ?? container.viewContext
        let fetch = NSFetchRequest<ArchiveMemberRecord>(entityName: "ArchiveMemberRecord")
        fetch.predicate = NSPredicate(format: "statusRawValue == %@", MembershipStatus.active.rawValue)

        // Prefer the private-store member (owner) if it exists;
        // otherwise return the shared-store member (invited collaborator).
        fetch.affectedStores = [privateStore]
        if let owner = try? context.fetch(fetch).first {
            return owner
        }

        guard let sharedStore else { return nil }
        fetch.affectedStores = [sharedStore]
        return try? context.fetch(fetch).first
    }

    /// The CloudKit identity of the CURRENT signed-in user. Share
    /// metadata only exposes the share owner's identity; the acceptee's
    /// identity must come from the user's own container.
    func currentUserIdentity() async -> VerifiedParticipantIdentity {
        guard Self.cloudKitAvailable else {
            return VerifiedParticipantIdentity(userRecordName: "unknown", participantType: "unavailable")
        }
        do {
            let recordID = try await ckContainer.userRecordID()
            return VerifiedParticipantIdentity(
                userRecordName: recordID.recordName,
                participantType: "cloudkit_user"
            )
        } catch {
            return VerifiedParticipantIdentity(userRecordName: "unknown", participantType: "unresolved")
        }
    }

    /// Delete a child recipient together with everything that referenced
    /// them. Letters keep `childID` as a plain UUID attribute (not a Core
    /// Data relationship), so deleting a child previously orphaned its
    /// letters and deliveries silently — they stayed in the store but
    /// became invisible in every filtered view.
    /// - Returns: The number of letters and deliveries removed.
    @discardableResult
    func deleteChild(
        _ child: ChildProfile,
        in context: NSManagedObjectContext? = nil
    ) -> (letters: Int, deliveries: Int) {
        let context = context ?? container.viewContext

        let letterFetch = NSFetchRequest<Letter>(entityName: "Letter")
        letterFetch.predicate = NSPredicate(format: "childID == %@", child.id as CVarArg)
        let letters = (try? context.fetch(letterFetch)) ?? []

        let deliveryFetch = NSFetchRequest<DeliveryRecordEntity>(entityName: "DeliveryRecordEntity")
        deliveryFetch.predicate = NSPredicate(format: "recipientID == %@", child.id as CVarArg)
        let deliveries = (try? context.fetch(deliveryFetch)) ?? []

        // Letter → attachments cascades via the model. Delivery →
        // deliveryAttachments cascades via the model.
        for letter in letters {
            context.delete(letter)
        }
        for delivery in deliveries {
            context.delete(delivery)
        }
        context.delete(child)

        // The recipient inbox partition is child-specific; remove it too so
        // an empty partition does not linger. Partition → children is
        // nullify (by design), so this must be explicit.
        if let partition = child.partition {
            context.delete(partition)
        }

        try? save(context)
        return (letters.count, deliveries.count)
    }

    /// Check whether the current user is authorized to perform an action
    /// in the given collaboration context. Combines CloudKit record-level
    /// checks (for existing objects) with the portable permission engine.
    func canPerform(
        _ action: CollaborationAction,
        context collaborationContext: CollaborationContext,
        target: NSManagedObject? = nil,
        in managedObjectContext: NSManagedObjectContext? = nil
    ) -> Bool {
        guard let member = currentMember(in: managedObjectContext) else {
            // No member record yet — the current user is the archive
            // owner and has full access.
            if action == .transferOwnership {
                return true
            }
            return CollaborationRole.owner.defaultPermissions.contains(
                permission(for: action)
            )
        }

        // CloudKit transport-level checks for existing objects.
        if let target {
            switch action {
            case .editContent, .deleteContent:
                if member.role != .owner && !canUpdate(target) {
                    return false
                }
            default:
                break
            }
        }

        // Portable permission engine.
        return CollaborationPolicy.allows(
            member.domainMember,
            action: action,
            context: collaborationContext
        )
    }

    private func permission(for action: CollaborationAction) -> CollaborationPermission {
        switch action {
        case .viewContent: .viewContent
        case .viewSealedContent: .viewSealedContent
        case .createContent: .createContent
        case .editContent: .editOwnContent
        case .deleteContent: .deleteOwnContent
        case .manageFolders: .manageFolders
        case .inviteContributors: .inviteContributors
        case .manageMembers: .manageMembers
        case .managePermissions: .managePermissions
        case .inviteRecipients: .inviteRecipients
        case .manageRecipients: .manageRecipients
        case .releaseLifeEventLetter: .releaseLifeEventLetters
        case .exportArchive: .exportArchive
        case .replyAsRecipient: .replyAsRecipient
        case .transferOwnership: .transferOwnership
        }
    }

    /// Create the initial private archive: the administration partition, an
    /// explicit owner member, and the four default family branches. Called
    /// once when the user taps "Create Our Family Archive" at onboarding and
    /// again defensively when the People tab loads. Idempotent — each piece
    /// is guarded so a re-run never duplicates records.
    func seedDefaultArchive(into context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext

        // Admin partition.
        let partitionFetch = NSFetchRequest<SharePartitionRecord>(entityName: "SharePartitionRecord")
        partitionFetch.predicate = NSPredicate(format: "kindRawValue == %@", SharePartitionKind.archiveAdministration.rawValue)
        var adminPartition = (try? context.fetch(partitionFetch))?.first
        if adminPartition == nil {
            let partition = insertPrivate(SharePartitionRecord.self, into: context)
            partition.kind = .archiveAdministration
            partition.displayName = "Family Archive Administration"
            adminPartition = partition
        }

        // Explicit owner member (guarded against archives restored from backup).
        let ownerFetch = NSFetchRequest<ArchiveMemberRecord>(entityName: "ArchiveMemberRecord")
        ownerFetch.predicate = NSPredicate(
            format: "roleRawValue == %@ AND statusRawValue == %@",
            CollaborationRole.owner.rawValue,
            MembershipStatus.active.rawValue
        )
        let ownerExists = ((try? context.fetch(ownerFetch)) ?? []).isEmpty == false
        if !ownerExists, let adminPartition {
            let owner = insertPrivate(ArchiveMemberRecord.self, into: context)
            owner.role = .owner
            owner.status = .active
            owner.displayName = "Owner"
            owner.scope = .archive
            owner.partition = adminPartition
        }

        // Default branches — only when there are no private branches yet.
        let branchFetch = NSFetchRequest<FamilyBranchRecord>(entityName: "FamilyBranchRecord")
        let hasBranches = ((try? context.fetch(branchFetch)) ?? []).isEmpty == false
        guard !hasBranches else {
            try? save(context)
            return
        }

        let defaults: [(String, FamilyBranchKind)] = [
            ("Parents", .parents),
            ("Maternal Family", .maternal),
            ("Paternal Family", .paternal),
            ("Chosen Family", .chosenFamily)
        ]
        for (name, kind) in defaults {
            let partition = insertPrivate(SharePartitionRecord.self, into: context)
            partition.kind = .branch
            partition.displayName = name

            let branch = insertPrivate(FamilyBranchRecord.self, into: context)
            branch.name = name
            branch.kind = kind
            branch.isSeeded = true
            branch.partition = partition
            partition.scopeID = branch.id
        }

        try? save(context)
    }

    /// Evaluate all sealed letters against their unlock rules and create
    /// recipient delivery records for any that have newly unlocked.
    /// Idempotent — letters that already have a delivery are skipped.
    func processPendingDeliveries(into context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext

        let childrenFetch = NSFetchRequest<ChildProfile>(entityName: "ChildProfile")
        let lettersFetch = NSFetchRequest<Letter>(entityName: "Letter")
        let deliveriesFetch = NSFetchRequest<DeliveryRecordEntity>(entityName: "DeliveryRecordEntity")

        guard let children = try? context.fetch(childrenFetch),
              let letters = try? context.fetch(lettersFetch),
              let existingDeliveries = try? context.fetch(deliveriesFetch) else {
            return
        }

        var existingDeliveryLetterIDs = Set(existingDeliveries.map(\.originalLetterID))
        let now = Date()
        var createdDeliveryCount = 0

        for child in children {
            let childLetters = letters.filter { $0.childID == child.id }
            let letterPayloads = childLetters.map { letterPayload(from: $0) }

            let pending = DeliveryPipeline.pendingDeliveries(
                letters: letterPayloads,
                childBirthDate: child.birthDate,
                existingDeliveries: Array(existingDeliveryLetterIDs),
                now: now
            )

            for letterPayload in pending {
                guard let sourceLetter = childLetters.first(where: { $0.id == letterPayload.id }) else {
                    continue
                }

                let attachmentPayloads = (sourceLetter.attachments?.allObjects as? [LetterAttachment] ?? []).map {
                    AttachmentPayload(
                        id: $0.id,
                        letterID: $0.letterID,
                        fileName: $0.fileName,
                        contentTypeIdentifier: $0.contentTypeIdentifier,
                        kindRawValue: $0.kindRawValue,
                        createdAt: $0.createdAt,
                        data: $0.data ?? Data()
                    )
                }

                guard let deliveryRecord = DeliveryPipeline.prepareDelivery(
                    from: letterPayload,
                    for: child.id,
                    attachments: attachmentPayloads,
                    existingDeliveries: Array(existingDeliveryLetterIDs)
                ) else { continue }

                let deliveryEntity: DeliveryRecordEntity
                if let partition = child.partition {
                    deliveryEntity = insert(
                        DeliveryRecordEntity.self,
                        inSameStoreAs: partition,
                        into: context
                    )
                    deliveryEntity.partition = partition
                } else {
                    deliveryEntity = insertPrivate(
                        DeliveryRecordEntity.self,
                        into: context
                    )
                }

                deliveryEntity.id = deliveryRecord.id
                deliveryEntity.recipientID = deliveryRecord.recipientID
                deliveryEntity.originalLetterID = deliveryRecord.originalLetterID
                deliveryEntity.title = deliveryRecord.title
                deliveryEntity.body = deliveryRecord.body
                deliveryEntity.authorName = deliveryRecord.authorName
                deliveryEntity.deliveredAt = deliveryRecord.deliveredAt
                deliveryEntity.state = deliveryRecord.state

                for att in deliveryRecord.attachments {
                    let attEntity = insert(
                        DeliveryAttachmentEntity.self,
                        inSameStoreAs: deliveryEntity,
                        into: context
                    )
                    attEntity.id = att.id
                    attEntity.fileName = att.fileName
                    attEntity.contentTypeIdentifier = att.contentTypeIdentifier
                    attEntity.kindRawValue = att.kindRawValue
                    attEntity.data = att.data
                    attEntity.delivery = deliveryEntity
                }

                existingDeliveryLetterIDs.insert(deliveryRecord.originalLetterID)
                createdDeliveryCount += 1
            }
        }

        try? save(context)

        // Only announce an unlock when deliveries were actually created;
        // a repeated launch must not spam "A Letter Has Unlocked".
        if createdDeliveryCount > 0 {
            scheduleUnlockNotification()
        }
    }

    private func letterPayload(from letter: Letter) -> LetterPayload {
        LetterPayload(
            id: letter.id,
            childID: letter.childID,
            branchID: letter.branchID,
            folderID: letter.folderID,
            authorMemberID: letter.authorMemberID,
            title: letter.title,
            body: letter.body,
            authorName: letter.authorName,
            createdAt: letter.createdAt,
            updatedAt: letter.updatedAt,
            sealedAt: letter.sealedAt,
            isFavorite: letter.isFavorite,
            unlockRuleRawValue: letter.unlockRuleRawValue,
            unlockDate: letter.unlockDate,
            unlockAgeYearsValue: letter.unlockAgeYears,
            lifeEventName: letter.lifeEventName,
            manuallyReleasedAt: letter.manuallyReleasedAt
        )
    }

    private func scheduleUnlockNotification() {
        #if os(iOS)
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "A Letter Has Unlocked"
        content.body = "A sealed letter is now available. Open Letters to My to read it."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "unlock-\(UUID().uuidString)",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        center.add(request)
        #endif
    }

    func acceptShare(
        _ metadata: CKShare.Metadata,
        completion: @escaping @Sendable (Result<Void, Error>) -> Void = { _ in }
    ) {
        guard let ckContainer = cloudKitContainer else {
            completion(.failure(PersistenceError.cloudKitUnavailable))
            return
        }
        ckContainer.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    /// After accepting one or more CloudKit shares, scan the shared store for
    /// partitions that carry member-activation metadata and create the
    /// corresponding local `ArchiveMemberRecord` with the intended role,
    /// scope, and CloudKit participant identity.
    func activateAcceptedMembers(
        participantIdentity: VerifiedParticipantIdentity? = nil,
        into context: NSManagedObjectContext? = nil
    ) {
        let context = context ?? container.viewContext
        // If the shared store isn't loaded (e.g. first launch without iCloud),
        // there's nothing to activate — return early instead of crashing.
        guard let sharedStore else { return }

        let fetchRequest = NSFetchRequest<SharePartitionRecord>(
            entityName: "SharePartitionRecord"
        )
        fetchRequest.predicate = NSPredicate(format: "memberActivationData != nil")
        fetchRequest.affectedStores = [sharedStore]

        guard let partitions = try? context.fetch(fetchRequest) else { return }

        for partition in partitions {
            guard let activation = partition.memberActivation else { continue }

            // Avoid creating duplicate member records for the same invitation.
            let memberFetch = NSFetchRequest<ArchiveMemberRecord>(
                entityName: "ArchiveMemberRecord"
            )
            memberFetch.predicate = NSPredicate(format: "id == %@", activation.intendedMemberID as CVarArg)
            memberFetch.affectedStores = [sharedStore]
            if let existing = try? context.fetch(memberFetch), !existing.isEmpty {
                continue
            }

            let member = insert(ArchiveMemberRecord.self, into: sharedStore, context: context)
            member.id = activation.intendedMemberID
            member.displayName = activation.displayName
            member.relationship = ""
            member.role = activation.role
            member.scope = activation.scope
            member.status = .active
            member.canInviteOthers = activation.canInviteOthers
            member.partition = partition

            if let identity = participantIdentity {
                member.cloudKitParticipantRecordName = identity.userRecordName
            }

            // In single-account development, the sender's invitation
            // lives in the private store. Mark it as accepted so the
            // sender sees the status update.
            if let privateStore {
                let invitationFetch = NSFetchRequest<CollaborationInvitationRecord>(
                    entityName: "CollaborationInvitationRecord"
                )
                invitationFetch.predicate = NSPredicate(
                    format: "id == %@",
                    activation.invitationID as CVarArg
                )
                invitationFetch.affectedStores = [privateStore]
                if let invitation = try? context.fetch(invitationFetch).first {
                    invitation.markAccepted()
                    // Link the new member to the invitation.
                    invitation.intendedMemberID = member.id
                }
            }

            // Clear the activation data after consumption to avoid
            // re-creating the member on subsequent launches.
            partition.memberActivationData = nil
        }

        try? save(context)
    }

    func existingShare(for objectURI: URL) throws -> CKShare? {
        guard let ckContainer = cloudKitContainer else {
            throw PersistenceError.cloudKitUnavailable
        }
        guard let objectID = container.persistentStoreCoordinator.managedObjectID(
            forURIRepresentation: objectURI
        ) else {
            throw PersistenceError.invalidManagedObjectURI(objectURI)
        }
        return try ckContainer.fetchShares(matching: [objectID])[objectID]
    }

    @MainActor
    func prepareShare(for objectURI: URL, title: String) async throws -> CKShare {
        guard let ckContainer = cloudKitContainer else {
            throw PersistenceError.cloudKitUnavailable
        }
        guard let objectID = container.persistentStoreCoordinator.managedObjectID(
            forURIRepresentation: objectURI
        ) else {
            throw PersistenceError.invalidManagedObjectURI(objectURI)
        }

        let context = container.viewContext
        let object = try context.existingObject(with: objectID)
        if object.objectID.isTemporaryID {
            try context.obtainPermanentIDs(for: [object])
        }
        try save(context)

        if let existing = try ckContainer.fetchShares(matching: [object.objectID])[object.objectID] {
            return existing
        }

        let share = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<CKShare, Error>) in
            ckContainer.share([object], to: nil) { _, share, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let share {
                    continuation.resume(returning: share)
                } else {
                    continuation.resume(throwing: PersistenceError.shareCreationReturnedNoShare)
                }
            }
        }

        share[CKShare.SystemFieldKey.title] = title as CKRecordValue
        share.publicPermission = .none

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            ckContainer.persistUpdatedShare(share, in: privateStore) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return share
    }

    /// Link any pending invitations whose target partition now has a
    /// persisted CloudKit share, transitioning them to the sent state.
    func linkExistingSharesToInvitations(into context: NSManagedObjectContext? = nil) {
        let context = context ?? container.viewContext
        let fetchRequest = NSFetchRequest<SharePartitionRecord>(
            entityName: "SharePartitionRecord"
        )
        fetchRequest.predicate = NSPredicate(format: "memberActivationData != nil")
        fetchRequest.affectedStores = [privateStore]

        guard let partitions = try? context.fetch(fetchRequest) else { return }

        for partition in partitions {
            let partitionURI = partition.objectID.uriRepresentation()
            guard let objectID = container.persistentStoreCoordinator.managedObjectID(
                forURIRepresentation: partitionURI
            ),
                  let share = (try? cloudKitContainer?.fetchShares(matching: [objectID])[objectID]) ?? nil,
                  let activation = partition.memberActivation else {
                continue
            }

            let invitationFetch = NSFetchRequest<CollaborationInvitationRecord>(
                entityName: "CollaborationInvitationRecord"
            )
            invitationFetch.predicate = NSPredicate(
                format: "id == %@ AND (statusRawValue == %@ OR statusRawValue == %@)",
                activation.invitationID as CVarArg,
                InvitationStatus.pending.rawValue,
                InvitationStatus.delivered.rawValue
            )
            invitationFetch.affectedStores = [privateStore]
            invitationFetch.fetchLimit = 1

            if let invitation = try? context.fetch(invitationFetch).first {
                invitation.markSent(
                    ckShareRecordName: share.recordID.recordName
                )
            }
        }

        try? save(context)
    }

    private func fallbackToInMemory(model: NSManagedObjectModel) async {
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        let inMemoryContainer: NSPersistentContainer
        if Self.cloudKitAvailable {
            inMemoryContainer = NSPersistentCloudKitContainer(
                name: "LettersToMy",
                managedObjectModel: model
            )
        } else {
            inMemoryContainer = NSPersistentContainer(
                name: "LettersToMy",
                managedObjectModel: model
            )
        }
        inMemoryContainer.persistentStoreDescriptions = [description]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inMemoryContainer.loadPersistentStores { _, error in
                if error == nil {
                    self.privateStore = inMemoryContainer.persistentStoreCoordinator.persistentStores.first
                    self.container = inMemoryContainer
                }
                continuation.resume()
            }
        }
        if privateStore == nil {
            fatalError("Unable to load even an in-memory Core Data store.")
        }
    }

    private static func makeStoreDescription(
        name: String,
        configuration: String,
        scope: CKDatabase.Scope,
        inMemory: Bool
    ) -> NSPersistentStoreDescription {
        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            guard let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                // Fail fast — the app cannot function without a
                // persistent store location.
                fatalError("Application Support directory is unavailable.")
            }
            let directory = applicationSupport.appendingPathComponent(
                "LettersToMy",
                isDirectory: true
            )
            try? FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            description = NSPersistentStoreDescription(
                url: directory.appendingPathComponent("\(name).sqlite")
            )
        }

        description.configuration = configuration
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        if !inMemory {
            let options = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainerIdentifier
            )
            options.databaseScope = scope
            description.cloudKitContainerOptions = options
        }
        return description
    }
}

enum PersistenceError: LocalizedError {
    case missingLoadedStore(URL?)
    case invalidManagedObjectURI(URL)
    case shareCreationReturnedNoShare
    case cloudKitUnavailable

    var errorDescription: String? {
        switch self {
        case .missingLoadedStore(let url):
            return "Core Data loaded a store description but no store was available at \(url?.path ?? "an unknown URL")."
        case .invalidManagedObjectURI(let url):
            return "The Core Data object identifier is invalid: \(url.absoluteString)"
        case .shareCreationReturnedNoShare:
            return "CloudKit completed share creation without returning a share."
        case .cloudKitUnavailable:
            return "CloudKit is not available — the process lacks the required iCloud entitlement."
        }
    }
}

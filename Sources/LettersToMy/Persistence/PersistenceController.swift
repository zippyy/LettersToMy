import CloudKit
import Combine
import CoreData
import Foundation

final class PersistenceController: ObservableObject, @unchecked Sendable {
    static let shared = PersistenceController()

    static let cloudKitContainerIdentifier = "iCloud.com.bayoumountainholdings.LettersToMy"
    static let privateConfigurationName = "Private"
    static let sharedConfigurationName = "Shared"

    let container: NSPersistentCloudKitContainer
    let cloudKitContainer: CKContainer

    private(set) var privateStore: NSPersistentStore!
    private(set) var sharedStore: NSPersistentStore!

    init(inMemory: Bool = false) {
        let model = LettersToMyManagedObjectModel.makeModel()
        container = NSPersistentCloudKitContainer(name: "LettersToMy", managedObjectModel: model)
        cloudKitContainer = CKContainer(identifier: Self.cloudKitContainerIdentifier)

        let privateDescription = Self.makeStoreDescription(
            name: "LettersToMy-private",
            configuration: Self.privateConfigurationName,
            scope: .private,
            inMemory: inMemory
        )
        let sharedDescription = Self.makeStoreDescription(
            name: "LettersToMy-shared",
            configuration: Self.sharedConfigurationName,
            scope: .shared,
            inMemory: inMemory
        )
        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        var loadingError: Error?
        let loadingGroup = DispatchGroup()
        loadingGroup.enter()
        loadingGroup.enter()

        container.loadPersistentStores { [weak self] description, error in
            defer { loadingGroup.leave() }
            guard let self else { return }
            if let error {
                loadingError = error
                return
            }

            guard let store = self.container.persistentStoreCoordinator.persistentStore(for: description.url!) else {
                loadingError = PersistenceError.missingLoadedStore(description.url)
                return
            }

            switch description.configuration {
            case Self.privateConfigurationName:
                self.privateStore = store
            case Self.sharedConfigurationName:
                self.sharedStore = store
            default:
                break
            }
        }

        loadingGroup.wait()
        if let loadingError {
            fatalError("Unable to load LettersToMy Core Data stores: \(loadingError)")
        }
        guard privateStore != nil, sharedStore != nil else {
            fatalError("LettersToMy did not load both the private and shared stores.")
        }

        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "LettersToMy.app"
        context.name = "LettersToMy.viewContext"
    }

    func save(_ context: NSManagedObjectContext? = nil) throws {
        let context = context ?? container.viewContext
        guard context.hasChanges else { return }
        try context.save()
    }

    func newBackgroundContext(author: String = "LettersToMy.background") -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = author
        return context
    }

    @discardableResult
    func insertPrivate<T: NSManagedObject>(
        _ type: T.Type,
        into context: NSManagedObjectContext? = nil
    ) -> T {
        let context = context ?? container.viewContext
        let entityName = String(describing: type)
        guard let object = NSEntityDescription.insertNewObject(
            forEntityName: entityName,
            into: context
        ) as? T else {
            fatalError("Unable to insert Core Data entity \(entityName).")
        }
        context.assign(object, to: privateStore)
        return object
    }

    func delete(_ object: NSManagedObject, from context: NSManagedObjectContext? = nil) {
        (context ?? object.managedObjectContext ?? container.viewContext).delete(object)
    }

    func canUpdate(_ object: NSManagedObject) -> Bool {
        container.canUpdateRecord(forManagedObjectWith: object.objectID)
    }

    func canDelete(_ object: NSManagedObject) -> Bool {
        container.canDeleteRecord(forManagedObjectWith: object.objectID)
    }

    func acceptShare(
        _ metadata: CKShare.Metadata,
        completion: @escaping (Result<Void, Error>) -> Void = { _ in }
    ) {
        container.acceptShareInvitations(from: [metadata], into: sharedStore) { _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(.failure(error))
                } else {
                    completion(.success(()))
                }
            }
        }
    }

    func existingShare(for objectURI: URL) throws -> CKShare? {
        guard let objectID = container.persistentStoreCoordinator.managedObjectID(
            forURIRepresentation: objectURI
        ) else {
            throw PersistenceError.invalidManagedObjectURI(objectURI)
        }
        return try container.fetchShares(matching: [objectID])[objectID]
    }

    @MainActor
    func prepareShare(for objectURI: URL, title: String) async throws -> CKShare {
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

        if let existing = try container.fetchShares(matching: [object.objectID])[object.objectID] {
            return existing
        }

        let share = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<CKShare, Error>) in
            container.share([object], to: nil) { _, share, _, error in
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
            container.persistUpdatedShare(share, in: privateStore) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        return share
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
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first!
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

    var errorDescription: String? {
        switch self {
        case .missingLoadedStore(let url):
            return "Core Data loaded a store description but no store was available at \(url?.path ?? "an unknown URL")."
        case .invalidManagedObjectURI(let url):
            return "The Core Data object identifier is invalid: \(url.absoluteString)"
        case .shareCreationReturnedNoShare:
            return "CloudKit completed share creation without returning a share."
        }
    }
}

import CoreData
import Foundation
import Testing
@testable import LettersToMy

/// Regression coverage for `PersistenceController` store bookkeeping.
///
/// `loadPersistentStores` reports progress per store description, and the
/// controller used to assign `privateStore` / `sharedStore` only from inside
/// those callbacks by matching the callback's `description.configuration`
/// against the coordinator. That is order- and identity-fragile: the
/// coordinator is the authoritative source once loading finishes, so the
/// controller must reconcile its references from the coordinator, not assume
/// each callback identifies the store it just described.
///
/// Invariant under test: after `loadStores()` completes, every store present
/// in the coordinator has the matching controller reference populated
/// (`privateStore` for the Private configuration, `sharedStore` for Shared),
/// and each reference points at that exact store instance.
@Suite(.serialized)
@MainActor
struct PersistenceStoreBookkeepingTests {

    private func makeController() async -> PersistenceController {
        // The bookkeeping under test is "both configured stores load and their
        // controller references point at the coordinator's instances". The
        // Test build configuration disables CloudKit, which by default loads
        // only the Private store — so the two-store configuration is requested
        // explicitly here. Without this the Shared-store regression would not
        // be exercised at all.
        let controller = PersistenceController(inMemory: true, includeSharedStore: true)
        await controller.loadStores()
        return controller
    }

    /// Describes what the coordinator actually holds. Kept as a test so the
    /// next person can see the real shape instead of guessing at callback
    /// ordering.
    @Test func coordinatorStateIsSelfConsistentAfterLoad() async {
        let controller = await makeController()
        let coordinator = controller.container.persistentStoreCoordinator

        let summaries = coordinator.persistentStores.map { store -> String in
            "config=\(store.configurationName) type=\(store.type) url=\(store.url?.lastPathComponent ?? "nil")"
        }
        print("PERSISTENCE-COORDINATOR-STORES: \(summaries)")

        // Whatever the configuration mix turns out to be, the private store
        // must always be resolvable — the app cannot function without it.
        #expect(controller.privateStore != nil)
        #expect(coordinator.persistentStores.contains { $0 === controller.privateStore })
    }

    /// The core invariant: a Shared-configuration store existing in the
    /// coordinator MUST be reflected in `sharedStore`. Any divergence here
    /// makes every `guard let sharedStore` production path silently no-op
    /// even though the store is available.
    @Test func sharedStoreReferenceMatchesCoordinator() async {
        let controller = await makeController()
        let coordinator = controller.container.persistentStoreCoordinator

        let coordinatorShared = coordinator.persistentStores.first {
            $0.configurationName == PersistenceController.sharedConfigurationName
        }

        if let coordinatorShared {
            let reference = controller.sharedStore
            #expect(reference != nil, "Coordinator holds a Shared store but sharedStore is nil")
            #expect(reference === coordinatorShared, "sharedStore must be the coordinator's Shared store instance")
        } else {
            #expect(controller.sharedStore == nil)
        }
    }

    /// Same identity guarantee for the private store.
    @Test func privateStoreReferenceMatchesCoordinator() async {
        let controller = await makeController()
        let coordinator = controller.container.persistentStoreCoordinator

        let coordinatorPrivate = coordinator.persistentStores.first {
            $0.configurationName == PersistenceController.privateConfigurationName
        }

        #expect(coordinatorPrivate != nil)
        #expect(controller.privateStore === coordinatorPrivate)
    }
}

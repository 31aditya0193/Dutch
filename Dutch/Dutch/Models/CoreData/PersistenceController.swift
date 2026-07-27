import CoreData
import CloudKit
import DutchKit

/// Core Data stack backed by `NSPersistentCloudKitContainer`.
///
/// Two stores are loaded, and both are required for sharing to work:
///
/// - the **private** store mirrors into the user's own CloudKit database and
///   holds the groups they created;
/// - the **shared** store receives groups other people have shared with them.
///
/// With only the private store, accepting an invitation appears to succeed but
/// the group never shows up, because there is nowhere for Core Data to put it.
final class PersistenceController {
    static let shared = PersistenceController()

    /// Must match the iCloud container in `Dutch.entitlements`.
    static let cloudKitContainerIdentifier = "iCloud.app.dutch.Dutch"

    /// Loaded exactly once and shared by every container.
    ///
    /// Letting each container load its own copy produces duplicate
    /// `NSEntityDescription`s for the same entity, and Core Data then logs
    /// "Failed to find a unique match for an NSEntityDescription" and picks
    /// one arbitrarily. That only shows up once a second stack exists — in
    /// tests, or alongside previews — so it is worth heading off here.
    static let managedObjectModel: NSManagedObjectModel = {
        guard let url = Bundle.main.url(forResource: "Dutch", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url)
        else {
            fatalError("Could not load the Dutch Core Data model from the app bundle.")
        }
        return model
    }()

    let container: NSPersistentCloudKitContainer

    /// The view context for main-queue reads, merging both local saves and
    /// changes that arrive from CloudKit.
    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    /// The store holding groups shared *with* this user. Needed when accepting
    /// an invitation.
    private(set) var sharedStore: NSPersistentStore?

    /// The store holding groups this user owns.
    private(set) var privateStore: NSPersistentStore?

    // MARK: - Init

    private init(inMemory: Bool = false) {
        // UI tests launch with a clean, local-only store so they neither
        // inherit state from a previous run nor depend on an iCloud account.
        let inMemory = inMemory
            || ProcessInfo.processInfo.arguments.contains("-uitesting-reset")

        container = NSPersistentCloudKitContainer(
            name: "Dutch",
            managedObjectModel: Self.managedObjectModel
        )

        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("NSPersistentCloudKitContainer has no store descriptions.")
        }

        if inMemory {
            // Previews and tests run without an iCloud account or entitlement,
            // so CloudKit mirroring is deliberately left off here.
            privateDescription.url = URL(fileURLWithPath: "/dev/null")
            privateDescription.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [privateDescription]
        } else {
            configureCloudKitStores(privateDescription: privateDescription)
        }

        container.loadPersistentStores { [weak container] description, error in
            if let error = error as NSError? {
                fatalError("Unresolved Core Data error: \(error), \(error.userInfo)")
            }
            guard let container, let url = description.url else { return }
            // Recorded so `CloudSharingService` knows which store to hand a
            // newly accepted share to.
            let store = container.persistentStoreCoordinator.persistentStore(for: url)
            if description.cloudKitContainerOptions?.databaseScope == .shared {
                self.sharedStore = store
            } else {
                self.privateStore = store
            }
        }

        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        viewContext.transactionAuthor = "app"

        if !inMemory {
            // Pins the context to a consistent snapshot so that merges arriving
            // mid-read don't surface half-applied state in the UI.
            //
            // Only for the real stores. The `/dev/null` store used by tests and
            // previews doesn't support query generations: `try?` hides the
            // failure here, and every later fetch then throws out of
            // `-[NSSQLCore currentQueryGeneration]` — which surfaces as the app
            // aborting inside whichever `@FetchRequest` renders first, with
            // nothing in the trace pointing back here.
            try? viewContext.setQueryGenerationFrom(.current)
        }
    }

    private func configureCloudKitStores(privateDescription: NSPersistentStoreDescription) {
        guard let privateURL = privateDescription.url else {
            fatalError("The private store description has no URL.")
        }

        // History tracking is a hard requirement for CloudKit mirroring, and
        // the remote-change notification is what lets the UI react to syncs.
        privateDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(
            true as NSNumber,
            forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey
        )

        let privateOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerIdentifier
        )
        privateOptions.databaseScope = .private
        privateDescription.cloudKitContainerOptions = privateOptions

        // The shared store mirrors the same model into the CloudKit shared
        // database, and needs its own file on disk.
        guard let sharedDescription = privateDescription.copy() as? NSPersistentStoreDescription else {
            fatalError("Could not derive the shared store description.")
        }
        sharedDescription.url = privateURL
            .deletingLastPathComponent()
            .appendingPathComponent("Dutch-shared.sqlite")

        let sharedOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: Self.cloudKitContainerIdentifier
        )
        sharedOptions.databaseScope = .shared
        sharedDescription.cloudKitContainerOptions = sharedOptions

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]
    }
}

// MARK: - Preview Support

extension PersistenceController {
    /// An in-memory instance for SwiftUI previews and tests.
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        let group = ExpenseGroup(context: context)
        group.id = UUID()
        group.name = "Berlin Trip"
        group.wordSequence = "green-moon-tea"
        group.creationDate = Date()
        group.currencyCode = "EUR"

        let alice = Person(context: context)
        alice.id = UUID()
        alice.name = "Alice"
        alice.group = group

        let bob = Person(context: context)
        bob.id = UUID()
        bob.name = "Bob"
        bob.group = group

        let expense = Expense(context: context)
        expense.id = UUID()
        expense.title = "Dinner"
        expense.amount = 45.00
        expense.date = Date()
        expense.paidBy = alice
        expense.group = group
        expense.splitAmong = NSSet(array: [alice, bob])

        try? context.save()
        return controller
    }()

    /// The sample group from `preview`, for views that require one.
    /// Traps if the sample data failed to build — previews only.
    static var previewGroup: ExpenseGroup {
        let request = ExpenseGroup.fetchRequest()
        request.fetchLimit = 1
        guard let group = try? preview.viewContext.fetch(request).first else {
            fatalError("Preview sample data is missing its ExpenseGroup.")
        }
        return group
    }
}

// MARK: - Background Context

extension PersistenceController {
    /// Creates a new background context tied to the same container.
    /// Use this for off-main-thread operations (imports, batch updates).
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.transactionAuthor = "app"
        return context
    }
}

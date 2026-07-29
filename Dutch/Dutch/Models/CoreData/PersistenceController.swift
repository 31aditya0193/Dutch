/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

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

    /// The shared store's file on disk.
    ///
    /// Named here rather than inline at the one place it is created, because
    /// `GroupLimit` identifies a joined group by which store it came from and
    /// has no other way to tell the two apart. A typo would silently make every
    /// group look like one the user created.
    static let sharedStoreFilename = "Dutch-shared.sqlite"

    /// Must match the app group in `Dutch.entitlements`.
    ///
    /// The stores live here rather than in the app's own container so that a
    /// second process on the same device can open them. An extension — the
    /// widget on the roadmap, or an App Intents extension — has a container of
    /// its own and simply cannot reach the app's; it would find no file and
    /// report an empty database rather than fail loudly.
    ///
    /// Unlike the iCloud container this one *is* prefixed with the bundle id,
    /// because an app group identifier has to be one the team owns and the
    /// bundle id is the obvious such name. Moving it later would strand every
    /// existing store, so it is fixed here for the same reason the iCloud
    /// container is.
    static let appGroupIdentifier = "group.net.smigi.Dutch"

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

        #if DEBUG
        // Trimmed before comparing: Xcode's launch-argument field preserves
        // whatever you typed, leading space included, and an exact match would
        // then silently do nothing — which looks identical to the schema
        // already being up to date.
        let wantsSchemaInit = ProcessInfo.processInfo.arguments.contains {
            $0.trimmingCharacters(in: .whitespaces) == "-initialize-cloudkit-schema"
        }
        if !inMemory, wantsSchemaInit {
            initializeCloudKitSchema()
        }
        #endif
    }

    #if DEBUG
    /// Pushes the whole managed object model to the **Development** CloudKit
    /// schema, then leaves it there to be promoted in the CloudKit Console.
    ///
    /// This exists because the container does not do it on its own. Fields are
    /// created in Development *lazily*, as records carrying them actually sync,
    /// so an attribute that no synced record has ever populated never reaches
    /// the schema at all — and there is then nothing to promote to Production.
    /// The failure shows up only in TestFlight or the App Store, which are the
    /// only builds that run against Production:
    ///
    ///     "Cannot create or modify field 'CD_colorName' in record
    ///      'CD_ExpenseGroup' in production schema"
    ///
    /// and it takes CloudKit mirroring down with it, so sharing stops working
    /// too. A debug build is unaffected and will keep looking perfect.
    ///
    /// **Run this after every model version**, before promoting the schema:
    ///
    ///     1. Run in Xcode, signed in to iCloud, with the launch argument
    ///        `-initialize-cloudkit-schema`.
    ///     2. CloudKit Console → this container → Schema → Deploy Schema
    ///        Changes → Production.
    ///     3. Remove the launch argument.
    ///
    /// Debug-only and argument-gated on purpose. It writes schema, it is slow,
    /// and Apple is explicit that it must never run in a shipping build.
    private func initializeCloudKitSchema() {
        do {
            try container.initializeCloudKitSchema(options: [])
            print("[Dutch] CloudKit development schema initialized. Now deploy it to Production in the CloudKit Console.")
        } catch {
            print("[Dutch] CloudKit schema initialization failed: \(error)")
        }
    }
    #endif

    /// Where the two store files live.
    ///
    /// The app group container when it is available, and the container Core
    /// Data picked otherwise. The fallback is deliberate: an entitlement that
    /// hasn't been provisioned yet returns `nil` here, and degrading to the
    /// app's own container costs a widget its data — while trapping would cost
    /// the user their app.
    private static func storeDirectory(fallingBackTo url: URL) -> URL {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
            ?? url.deletingLastPathComponent()
    }

    private func configureCloudKitStores(privateDescription: NSPersistentStoreDescription) {
        guard let defaultURL = privateDescription.url else {
            fatalError("The private store description has no URL.")
        }

        // Both stores keep the filenames Core Data chose, in whichever
        // directory is reachable from every process that needs them.
        let directory = Self.storeDirectory(fallingBackTo: defaultURL)
        privateDescription.url = directory.appendingPathComponent(defaultURL.lastPathComponent)

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
        sharedDescription.url = directory.appendingPathComponent(Self.sharedStoreFilename)

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

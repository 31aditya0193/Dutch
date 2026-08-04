/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
@testable import Dutch

/// A fresh, isolated in-memory Core Data stack per call, so tests don't share
/// state.
///
/// Plain `NSPersistentContainer`, not the CloudKit one — these tests are about
/// the data model and the settlement bridge, and mirroring would only add an
/// iCloud account dependency. The model is found in the app bundle, which is
/// the test host.
///
/// It reuses `PersistenceController.managedObjectModel` rather than loading its
/// own copy, and that is load-bearing: a second `NSManagedObjectModel` over the
/// same entities produces duplicate `NSEntityDescription`s, at which point Core
/// Data logs "Failed to find a unique match" and picks one arbitrarily. Tests
/// are the main place a second stack ever exists, so they are also the main
/// place that bites.
///
/// `GroupLimitTests` deliberately does *not* use this — it needs an on-disk
/// store, because it asserts on `objectID.persistentStore` and an in-memory
/// store has no URL to tell the private and shared stores apart.
enum TestStack {
    static func makeContext() -> NSManagedObjectContext {
        let container = NSPersistentContainer(
            name: "Dutch",
            managedObjectModel: PersistenceController.managedObjectModel
        )

        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        precondition(loadError == nil, "In-memory store failed to load: \(loadError!)")

        return container.viewContext
    }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import Testing
@testable import Dutch

/// Tests for the free-tier rule.
///
/// The one that matters is `joinedGroupsDoNotCount`. Everything else here is
/// arithmetic; that one is the business model, and it is enforced by a detail —
/// which persistent store an object came from — that nothing else in the app
/// reads. A refactor that broke it would put a paywall in front of somebody
/// scanning a QR code at a dinner table, and no other test would notice.
@MainActor
@Suite("GroupLimit")
struct GroupLimitTests {

    /// A coordinator with both stores loaded, mirroring the real stack.
    ///
    /// On-disk SQLite rather than in-memory, because the rule reads the store's
    /// *URL* and an in-memory store has none — testing this against in-memory
    /// stores would pass while asserting nothing.
    private static func makeTwoStoreContext() throws -> (
        context: NSManagedObjectContext,
        privateStore: NSPersistentStore,
        sharedStore: NSPersistentStore,
        directory: URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let coordinator = NSPersistentStoreCoordinator(
            managedObjectModel: PersistenceController.managedObjectModel
        )

        let privateStore = try coordinator.addPersistentStore(
            type: .sqlite,
            at: directory.appendingPathComponent("Dutch.sqlite")
        )
        let sharedStore = try coordinator.addPersistentStore(
            type: .sqlite,
            at: directory.appendingPathComponent(PersistenceController.sharedStoreFilename)
        )

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        return (context, privateStore, sharedStore, directory)
    }

    /// Inserts a group into a named store. With two stores and no model
    /// configurations, Core Data cannot pick one on its own.
    private static func makeGroup(
        named name: String,
        in store: NSPersistentStore,
        context: NSManagedObjectContext
    ) -> ExpenseGroup {
        let group = ExpenseGroup(context: context)
        group.id = UUID()
        group.name = name
        group.creationDate = Date()
        context.assign(group, to: store)
        return group
    }

    // MARK: - Which groups count

    @Test("Groups the user joined never count toward the limit")
    func joinedGroupsDoNotCount() throws {
        let stack = try Self.makeTwoStoreContext()
        defer { try? FileManager.default.removeItem(at: stack.directory) }

        let mine = Self.makeGroup(named: "Berlin Trip", in: stack.privateStore, context: stack.context)
        let theirs = Self.makeGroup(named: "Ski Weekend", in: stack.sharedStore, context: stack.context)
        let alsoTheirs = Self.makeGroup(named: "Lunch Club", in: stack.sharedStore, context: stack.context)
        try stack.context.save()

        #expect(GroupLimit.isJoined(mine) == false)
        #expect(GroupLimit.isJoined(theirs))
        #expect(GroupLimit.isJoined(alsoTheirs))

        let all = [mine, theirs, alsoTheirs]
        #expect(GroupLimit.createdCount(among: all) == 1)

        // The case the model exists for: one group of their own, plus any
        // number of invitations accepted, and still no paywall in sight.
        #expect(GroupLimit.canCreate(among: all, unlocked: false) == false)
        #expect(GroupLimit.createdCount(among: [theirs, alsoTheirs]) == 0)
        #expect(GroupLimit.canCreate(among: [theirs, alsoTheirs], unlocked: false))
    }

    @Test("A group the user created and then shared still counts as theirs")
    func sharingAGroupDoesNotMoveIt() throws {
        let stack = try Self.makeTwoStoreContext()
        defer { try? FileManager.default.removeItem(at: stack.directory) }

        let mine = Self.makeGroup(named: "Berlin Trip", in: stack.privateStore, context: stack.context)
        mine.cloudKitShareURL = URL(string: "https://www.icloud.com/share/0ABCdef")
        try stack.context.save()

        #expect(GroupLimit.isJoined(mine) == false)
        #expect(GroupLimit.createdCount(among: [mine]) == 1)
    }

    // MARK: - The limit itself

    @Test("The first group is free")
    func firstGroupIsFree() throws {
        let stack = try Self.makeTwoStoreContext()
        defer { try? FileManager.default.removeItem(at: stack.directory) }

        #expect(GroupLimit.canCreate(among: [ExpenseGroup](), unlocked: false))

        let mine = Self.makeGroup(named: "Berlin Trip", in: stack.privateStore, context: stack.context)
        try stack.context.save()

        #expect(GroupLimit.canCreate(among: [mine], unlocked: false) == false)
    }

    @Test("The purchase lifts the limit entirely")
    func purchaseUnlocks() throws {
        let stack = try Self.makeTwoStoreContext()
        defer { try? FileManager.default.removeItem(at: stack.directory) }

        let groups = (1...5).map {
            Self.makeGroup(named: "Trip \($0)", in: stack.privateStore, context: stack.context)
        }
        try stack.context.save()

        #expect(GroupLimit.canCreate(among: groups, unlocked: false) == false)
        #expect(GroupLimit.canCreate(among: groups, unlocked: true))
    }

    @Test("Deleting the free group frees the slot again")
    func deletingFreesTheSlot() throws {
        let stack = try Self.makeTwoStoreContext()
        defer { try? FileManager.default.removeItem(at: stack.directory) }

        let mine = Self.makeGroup(named: "Berlin Trip", in: stack.privateStore, context: stack.context)
        try stack.context.save()
        #expect(GroupLimit.canCreate(among: [mine], unlocked: false) == false)

        // What the paywall tells a free user they can do, so it had better be
        // true: the limit is on groups held, not on groups ever created.
        stack.context.delete(mine)
        try stack.context.save()

        #expect(GroupLimit.canCreate(among: [ExpenseGroup](), unlocked: false))
    }
}

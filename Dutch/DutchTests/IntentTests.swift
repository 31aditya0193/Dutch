/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit
import Testing
@testable import Dutch

/// Covers the seam App Intents sit on: finding a group from a string somebody
/// said or typed, and recording an expense with no screen involved.
///
/// The intents themselves can only be *run* by the system, so what is tested
/// here is everything up to and including the write — group resolution, the
/// identity requirement, and what actually lands in the store.
@MainActor
@Suite("Intents")
struct IntentTests {

    /// A fresh, isolated in-memory stack per test, exactly as `GroupStoreTests`
    /// builds one — plain `NSPersistentContainer`, so no iCloud account is
    /// needed and nothing mirrors.
    private static func makeContext() -> NSManagedObjectContext {
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

    // MARK: - Finding a group

    @Test("A group is found by its id")
    func findsByID() throws {
        let context = Self.makeContext()
        let group = try GroupStore(context: context).createGroup(named: "Berlin Trip")
        let id = try #require(group.id)

        #expect(GroupLookup.group(id: id, in: context) == group)
        #expect(GroupLookup.group(id: UUID(), in: context) == nil)
    }

    @Test("A group is found by part of its name, ignoring case")
    func findsByName() throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let berlin = try store.createGroup(named: "Berlin Trip")
        try store.createGroup(named: "Ski Weekend")

        #expect(GroupLookup.groups(matching: "berlin", in: context) == [berlin])
        #expect(GroupLookup.groups(matching: "Berlin Trip", in: context) == [berlin])
        #expect(GroupLookup.groups(matching: "Lisbon", in: context).isEmpty)
    }

    /// The whole reason the word sequence is printed next to the QR code: it is
    /// a name people can say. Siri hears it as three words with spaces, and
    /// older builds wrote other separators.
    @Test("A group is found by its word sequence, however it is written")
    func findsByWordSequence() throws {
        let context = Self.makeContext()
        let group = try GroupStore(context: context).createGroup(named: "Berlin Trip")
        group.wordSequence = "coral-lotus-pearl"
        try context.save()

        for spoken in [
            "coral-lotus-pearl",
            "coral lotus pearl",
            "Coral Lotus Pearl",
            "coral.lotus.pearl",
            "coral~lotus~pearl",
        ] {
            #expect(
                GroupLookup.groups(matching: spoken, in: context) == [group],
                "\(spoken) should find the group"
            )
        }
    }

    /// A partial sequence must not match. It is a whole identifier, and half of
    /// one would pick a group at random out of however many share those words.
    @Test("A partial word sequence finds nothing")
    func partialSequenceFindsNothing() throws {
        let context = Self.makeContext()
        let group = try GroupStore(context: context).createGroup(named: "Berlin Trip")
        group.wordSequence = "coral-lotus-pearl"
        try context.save()

        #expect(GroupLookup.groups(matching: "coral-lotus", in: context).isEmpty)
    }

    @Test("Empty input finds nothing rather than everything")
    func emptyInputFindsNothing() throws {
        let context = Self.makeContext()
        try GroupStore(context: context).createGroup(named: "Berlin Trip")

        #expect(GroupLookup.groups(matching: "", in: context).isEmpty)
        #expect(GroupLookup.groups(matching: "   ", in: context).isEmpty)
    }

    @Test("Every group is offered newest first")
    func suggestsNewestFirst() throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let older = try store.createGroup(named: "Ski Weekend")
        older.creationDate = Date(timeIntervalSince1970: 0)
        let newer = try store.createGroup(named: "Berlin Trip")
        newer.creationDate = Date()
        try context.save()

        #expect(GroupLookup.all(in: context) == [newer, older])
    }

    // MARK: - Last opened

    @Test("The last opened group survives a round trip and is dropped on delete")
    func lastOpened() throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")
        let id = try #require(group.id)

        ExpenseDefaults.rememberOpened(group)
        #expect(ExpenseDefaults.lastOpenedGroupID == id)
        #expect(GroupLookup.lastOpened(in: context) == group)

        // Otherwise the Action button and the Home Screen action would keep
        // pointing at a group that no longer exists.
        try store.delete(group)
        #expect(ExpenseDefaults.lastOpenedGroupID == nil)
        #expect(GroupLookup.lastOpened(in: context) == nil)
    }

    /// A phone with one group has nothing to disambiguate, so an intent that
    /// asked which one would be asking for the sake of it.
    @Test("With one group and nothing opened yet, that group is the answer")
    func fallsBackToTheOnlyGroup() throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let only = try store.createGroup(named: "Berlin Trip")

        #expect(GroupLookup.lastOpened(in: context) == nil)
        #expect(GroupLookup.all(in: context) == [only])

        // A second group makes it ambiguous again, and the intent has to ask.
        try store.createGroup(named: "Ski Weekend")
        #expect(GroupLookup.all(in: context).count == 2)
    }

    @Test("Deleting a different group leaves the last opened one alone")
    func lastOpenedSurvivesUnrelatedDelete() throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let kept = try store.createGroup(named: "Berlin Trip")
        let doomed = try store.createGroup(named: "Ski Weekend")
        let keptID = try #require(kept.id)

        ExpenseDefaults.rememberOpened(kept)
        try store.delete(doomed)

        #expect(ExpenseDefaults.lastOpenedGroupID == keptID)
    }

    // MARK: - Adding an expense

    @Test("An expense added by intent is paid by you and split among everyone")
    func addsExpense() async throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip", currencyCode: "EUR")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)
        ExpenseDefaults.rememberMe(alice, in: group)

        try IntentWriter.addExpense(
            title: "Dinner",
            amount: 30.00,
            to: group,
            in: context
        )

        let expense = try #require(group.spending.first)
        #expect(group.spending.count == 1)
        #expect(expense.title == "Dinner")
        #expect(Money(amount: expense.amount) == Money(amount: 30.00))
        #expect(expense.paidBy == alice)
        #expect((expense.splitAmong as? Set<Person>) == Set([alice, bob]))
        // Half each, and Alice is square with herself for her own half.
        #expect(
            group.settlement().balanceByParticipant[try #require(bob.id)]
                == Money(amount: -15.00)
        )
    }

    /// Without an identity there is nobody to record as having paid, and
    /// guessing would put a wrong number in a shared group. The intent has to
    /// refuse and say why.
    @Test("Adding an expense without an identity fails rather than guessing")
    func refusesWithoutIdentity() throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")
        try store.addMember(named: "Alice", to: group)
        ExpenseDefaults.rememberMe(nil, in: group)

        #expect(throws: DutchIntentError.self) {
            try IntentWriter.addExpense(title: "Dinner", amount: 30, to: group, in: context)
        }
        #expect(group.spending.isEmpty)
    }

    @Test("Adding an expense to an empty group fails rather than saving nothing")
    func refusesWithoutMembers() throws {
        let context = Self.makeContext()
        let group = try GroupStore(context: context).createGroup(named: "Berlin Trip")

        #expect(throws: DutchIntentError.self) {
            try IntentWriter.addExpense(title: "Dinner", amount: 30, to: group, in: context)
        }
        #expect(group.spending.isEmpty)
    }
}

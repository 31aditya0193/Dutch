import CoreData
import DutchKit
import Testing
@testable import Dutch

/// End-to-end tests over a real (in-memory) Core Data stack: create a group,
/// add members and expenses, and confirm the balances the UI would render.
///
/// These cover the seam that the pure `DutchKit` tests cannot — that the
/// Core Data objects map onto the value types correctly.
@MainActor
@Suite("GroupStore")
struct GroupStoreTests {

    /// A fresh, isolated in-memory stack per test so they don't share state.
    ///
    /// Plain `NSPersistentContainer`, not the CloudKit one — these tests are
    /// about the data model and settlement bridge, and mirroring would only
    /// add an iCloud account dependency. The model is found in the app bundle,
    /// which is the test host.
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

    // MARK: - Creating

    @Test("Creating a group assigns an id, date and word sequence")
    func createGroup() throws {
        let store = GroupStore(context: Self.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")

        #expect(group.name == "Berlin Trip")
        #expect(group.id != nil)
        #expect(group.creationDate != nil)

        let sequence = try #require(group.wordSequence)
        #expect(WordGenerator.isWellFormed(sequence))
    }

    @Test("Members attach to their group")
    func addMembers() throws {
        let store = GroupStore(context: Self.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")

        try store.addMember(named: "Alice", to: group)
        try store.addMember(named: "Bob", to: group)

        #expect(group.members?.count == 2)
        #expect(group.roster.map(\.name) == ["Alice", "Bob"])
    }

    @Test("Deleting a group cascades to its members and expenses")
    func deleteCascades() throws {
        let context = Self.makeContext()
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        try store.addExpense(
            title: "Dinner",
            amount: Money(cents: 1000),
            paidBy: alice,
            splitAmong: [alice],
            in: group
        )

        try store.delete(group)

        #expect(try context.count(for: ExpenseGroup.fetchRequest()) == 0)
        #expect(try context.count(for: Person.fetchRequest()) == 0)
        #expect(try context.count(for: Expense.fetchRequest()) == 0)
    }

    // MARK: - Balances through the bridge

    @Test("A split expense produces the balances the detail screen shows")
    func balancesAfterExpense() throws {
        let store = GroupStore(context: Self.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner",
            amount: Money(amount: 30.00),
            paidBy: alice,
            splitAmong: [alice, bob],
            in: group
        )

        let balances = group.balances
        #expect(balances.count == 2)

        let aliceBalance = try #require(balances.first { $0.participant.name == "Alice" })
        let bobBalance = try #require(balances.first { $0.participant.name == "Bob" })

        #expect(aliceBalance.amount == Money(cents: 1500))
        #expect(bobBalance.amount == Money(cents: -1500))
    }

    @Test("The settle-up list points from the debtor to the payer")
    func transfersAfterExpense() throws {
        let store = GroupStore(context: Self.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Dinner",
            amount: Money(amount: 30.00),
            paidBy: alice,
            splitAmong: [alice, bob],
            in: group
        )

        let transfers = group.transfers
        #expect(transfers.count == 1)
        #expect(transfers.first?.from.name == "Bob")
        #expect(transfers.first?.to.name == "Alice")
        #expect(transfers.first?.amount == Money(cents: 1500))
    }

    /// The behaviour the "Split Among" footer describes: a payer left out of
    /// the split is covering the cost for others and is owed all of it.
    @Test("Paying on someone else's behalf is recorded in full")
    func payerExcludedFromSplit() throws {
        let store = GroupStore(context: Self.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)

        try store.addExpense(
            title: "Bob's ticket",
            amount: Money(amount: 20.00),
            paidBy: alice,
            splitAmong: [bob],
            in: group
        )

        let aliceBalance = try #require(group.balances.first { $0.participant.name == "Alice" })
        #expect(aliceBalance.amount == Money(cents: 2000))
    }

    @Test("A group with no expenses still lists its members at zero")
    func emptyGroupBalances() throws {
        let store = GroupStore(context: Self.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        try store.addMember(named: "Alice", to: group)
        try store.addMember(named: "Bob", to: group)

        let balances = group.balances
        #expect(balances.count == 2)
        let allZero = balances.allSatisfy { $0.amount.isZero }
        #expect(allZero)
        #expect(group.transfers.isEmpty)
    }

    @Test("Amounts entered in major units survive the round trip to cents")
    func amountRoundTrip() throws {
        let store = GroupStore(context: Self.makeContext())
        let group = try store.createGroup(named: "Berlin Trip")
        let alice = try store.addMember(named: "Alice", to: group)
        let bob = try store.addMember(named: "Bob", to: group)
        let carol = try store.addMember(named: "Carol", to: group)

        // 10.00 three ways is the classic case for losing a cent.
        try store.addExpense(
            title: "Taxi",
            amount: Money(amount: 10.00),
            paidBy: alice,
            splitAmong: [alice, bob, carol],
            in: group
        )

        let total = group.balances.reduce(Money.zero) { $0 + $1.amount }
        #expect(total == .zero)
    }
}

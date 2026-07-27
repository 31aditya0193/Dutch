import CoreData
import DutchKit

/// Write operations on groups.
///
/// Reads deliberately live in `@FetchRequest` instead of here. A hand-rolled
/// fetch into an array only refreshes when something calls it again, so changes
/// arriving from CloudKit would never reach the UI — which is most of the point
/// of this app.
struct GroupStore {
    let context: NSManagedObjectContext

    @discardableResult
    func createGroup(named name: String, currencyCode: String? = nil) throws -> ExpenseGroup {
        let group = ExpenseGroup(context: context)
        group.id = UUID()
        group.name = name
        group.wordSequence = WordGenerator.generate()
        group.creationDate = Date()
        // Pinned at creation so the group reads the same on every member's
        // device, whatever locale they happen to be in.
        group.currencyCode = currencyCode ?? Locale.current.currency?.identifier ?? "USD"

        try context.save()
        return group
    }

    @discardableResult
    func addMember(named name: String, to group: ExpenseGroup) throws -> Person {
        let person = Person(context: context)
        person.id = UUID()
        person.name = name
        person.group = group

        try context.save()
        return person
    }

    /// Deletes a group along with its members and expenses, via the model's
    /// cascade rules.
    func delete(_ group: ExpenseGroup) throws {
        // Before the delete, not after: once the context has saved, `group` is
        // an invalidated object and reading `id` off it to build the key is no
        // longer safe. If the save then fails, the cost is a forgotten default
        // that the next saved expense sets again.
        ExpenseDefaults.forget(group)
        context.delete(group)
        try context.save()
    }

    func delete(_ expense: Expense) throws {
        context.delete(expense)
        try context.save()
    }

    /// Removes a member, along with every expense they paid for.
    ///
    /// The model nullifies `paidBy` on delete, which would leave those expenses
    /// payer-less. `Expense.entry` then drops them, so the money would vanish
    /// from the split without ever appearing as a deletion — the balances would
    /// simply be wrong. Removing them outright is the honest behaviour, and the
    /// UI warns before calling this.
    func delete(_ member: Person) throws {
        for case let expense as Expense in member.paidExpenses ?? [] {
            context.delete(expense)
        }
        context.delete(member)
        try context.save()
    }

    func addExpense(
        title: String,
        amount: Money,
        paidBy payer: Person,
        splitAmong participants: Set<Person>,
        in group: ExpenseGroup
    ) throws {
        let expense = Expense(context: context)
        expense.id = UUID()
        expense.title = title
        expense.amount = amount.amount
        expense.date = Date()
        expense.paidBy = payer
        expense.group = group
        expense.splitAmong = NSSet(set: participants)

        try context.save()
    }
}

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
    func createGroup(named name: String) throws -> ExpenseGroup {
        let group = ExpenseGroup(context: context)
        group.id = UUID()
        group.name = name
        group.wordSequence = WordGenerator.generate()
        group.creationDate = Date()

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
        context.delete(group)
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

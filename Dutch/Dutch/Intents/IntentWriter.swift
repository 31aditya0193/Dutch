import CoreData
import DutchKit

/// Recording an expense with no screen involved.
///
/// Split out of `AddExpenseIntent` for two reasons. It takes its context as an
/// argument, so it can be tested against an in-memory stack — an `AppIntent`
/// reaches for `PersistenceController.shared` and cannot. And it is the part a
/// second front end would reuse verbatim: the intent above it is a description
/// of an action, while this is the action.
///
/// The storage itself still goes through `GroupStore`, which already took every
/// field this needs. What lives here is the policy an intent has to apply
/// because there is no form to apply it: who paid, and who shares.
enum IntentWriter {

    /// Records an expense paid by whoever this device belongs to, split evenly
    /// between every member.
    ///
    /// Returns the payer, so the caller can say where that leaves them without
    /// looking the same person up twice.
    ///
    /// Throws rather than falling back on either count. A group with no members
    /// has nobody to charge, and a device with no identity has nobody to credit
    /// — and picking somebody plausible would put a wrong number into a group
    /// other people are reading, which is worse than not recording it at all.
    @discardableResult
    @MainActor
    static func addExpense(
        title: String,
        amount: Double,
        to group: ExpenseGroup,
        in context: NSManagedObjectContext
    ) throws -> Person {
        let name = group.name ?? "this group"

        let members = (group.members as? Set<Person>) ?? []
        guard !members.isEmpty else { throw DutchIntentError.noMembers(group: name) }

        guard let payer = ExpenseDefaults.me(in: group, among: Array(members)) else {
            throw DutchIntentError.noIdentity(group: name)
        }

        do {
            try GroupStore(context: context).addExpense(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                // Always the group's own currency. An expense paid abroad needs
                // a rate, rates are frozen at entry on purpose, and there is no
                // way to ask "at what rate?" in a voice flow without guessing —
                // which is the exact failure that decision exists to prevent.
                // Foreign receipts go through the form.
                amount: Money(amount: amount),
                paidBy: payer,
                // Everyone, because that is what an expense entered in one
                // sentence means. Leaving somebody out is a decision, and a
                // decision needs a screen.
                splitAmong: members,
                in: group
            )
        } catch {
            throw DutchIntentError.saveFailed(error.localizedDescription)
        }

        return payer
    }
}

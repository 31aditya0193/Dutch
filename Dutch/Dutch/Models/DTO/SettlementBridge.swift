import CoreData
import DutchKit

/// Maps Core Data objects onto the storage-independent value types in
/// `DutchKit`. Keeping the conversion in one place means the settlement maths
/// never has to know that Core Data exists, and stays testable without a stack.

extension Person {
    /// `nil` when the record is incomplete — CloudKit requires every attribute
    /// to be optional, so a partially synced record is representable.
    var participant: Participant? {
        guard let id, let name else { return nil }
        return Participant(id: id, name: name)
    }
}

extension Expense {
    /// `nil` when the expense has no id or no payer, in which case it cannot
    /// contribute to a balance.
    var entry: ExpenseEntry? {
        guard let id, let payerID = paidBy?.id else { return nil }

        let sharers = (splitAmong as? Set<Person>)?.compactMap(\.id) ?? []

        return ExpenseEntry(
            id: id,
            amount: Money(amount: amount),
            payer: payerID,
            sharedBetween: Set(sharers)
        )
    }
}

extension ExpenseGroup {
    /// Every member that is complete enough to take part in a split.
    var roster: [Participant] {
        (members as? Set<Person>)?
            .compactMap(\.participant)
            .sorted { $0.name < $1.name } ?? []
    }

    var entries: [ExpenseEntry] {
        (expenses as? Set<Expense>)?.compactMap(\.entry) ?? []
    }

    /// Net position per member, including members who come out even.
    var balances: [Balance] {
        SettlementCalculator.balances(for: entries, roster: roster)
    }

    /// The payments that would settle the group.
    var transfers: [Transfer] {
        SettlementCalculator.transfers(settling: balances)
    }
}

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

    /// Everything the group has spent, whoever paid for it.
    var totalSpent: Money {
        entries.reduce(Money.zero) { $0 + $1.amount }
    }

    /// True when nobody owes anybody — including a group with no expenses yet.
    var isSettled: Bool {
        balances.allSatisfy(\.amount.isZero)
    }
}

// MARK: - Composite

extension ExpenseGroup {
    /// Everything a screen derives from a group's contents, from one pass.
    ///
    /// Each accessor above is honest on its own but rebuilds `entries` and
    /// `roster` from the relationship sets, and `transfers` runs `balances`
    /// again on top of that. Reading several of them — which every screen in
    /// the app does — pays for that walk once per reading, and reading one
    /// *per row* pays for it once per row.
    struct Settlement {
        let transfers: [Transfer]
        let totalSpent: Money

        /// Net position keyed by participant, because the screens that show a
        /// balance show one per member row. Scanning the ordered `balances`
        /// array per row is quadratic in members; the ordered form is still on
        /// the group itself for anyone who wants it.
        let balanceByParticipant: [Participant.ID: Money]
    }

    /// Computes the group's settlement in a single pass over its members and
    /// expenses.
    ///
    /// A method rather than a property, deliberately: this is not free, and a
    /// call site should read like it costs something. Take one per render and
    /// pass it down — don't call it per row.
    func settlement() -> Settlement {
        let roster = roster
        let entries = entries
        let balances = SettlementCalculator.balances(for: entries, roster: roster)

        return Settlement(
            transfers: SettlementCalculator.transfers(settling: balances),
            totalSpent: entries.reduce(Money.zero) { $0 + $1.amount },
            balanceByParticipant: Dictionary(
                balances.map { ($0.participant.id, $0.amount) },
                uniquingKeysWith: { first, _ in first }
            )
        )
    }
}

// MARK: - Currency

extension ExpenseGroup {
    /// The currency every amount in this group is expressed in.
    ///
    /// Stored on the group rather than read from `Locale.current` at display
    /// time. A group shared between someone in Kraków and someone in Berlin is
    /// still one bill in one currency, and rendering the same cents as `zł` on
    /// one device and `€` on the other would be quietly, unfixably wrong.
    ///
    /// Optional in the model because CloudKit requires it, so groups created
    /// before this attribute existed fall back to the reader's own locale.
    var currency: String {
        currencyCode ?? Locale.current.currency?.identifier ?? "USD"
    }
}

extension Money {
    /// Formats in the currency the given group is denominated in.
    func formatted(in group: ExpenseGroup) -> String {
        formatted(currencyCode: group.currency)
    }
}

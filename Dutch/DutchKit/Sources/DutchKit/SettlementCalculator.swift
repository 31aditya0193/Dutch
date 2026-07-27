import Foundation

// MARK: - Inputs

/// A member of a group, identified independently of any storage layer.
public struct Participant: Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A single expense: who paid, how much, and who it is shared between.
public struct ExpenseEntry: Hashable, Sendable {
    public let id: UUID
    public let amount: Money
    /// The participant who actually paid the bill.
    public let payer: Participant.ID
    /// Everyone the cost is divided between.
    ///
    /// Include the payer here when they also consumed part of the expense.
    /// Leave them out when they paid purely on someone else's behalf — the
    /// calculator never adds the payer implicitly.
    public let sharedBetween: Set<Participant.ID>

    public init(
        id: UUID,
        amount: Money,
        payer: Participant.ID,
        sharedBetween: Set<Participant.ID>
    ) {
        self.id = id
        self.amount = amount
        self.payer = payer
        self.sharedBetween = sharedBetween
    }
}

// MARK: - Outputs

/// What a participant is net owed (positive) or owes (negative).
public struct Balance: Hashable, Identifiable, Sendable {
    public let participant: Participant
    public let amount: Money

    public var id: Participant.ID { participant.id }

    public init(participant: Participant, amount: Money) {
        self.participant = participant
        self.amount = amount
    }
}

/// One payment that moves the group closer to settled.
public struct Transfer: Hashable, Identifiable, Sendable {
    public let from: Participant
    public let to: Participant
    public let amount: Money

    public var id: String { "\(from.id)->\(to.id)" }

    public init(from: Participant, to: Participant, amount: Money) {
        self.from = from
        self.to = to
        self.amount = amount
    }
}

// MARK: - Calculator

/// Works out who owes whom. Pure value-type logic with no storage or UI
/// dependency, so it can be tested without a Core Data stack.
public enum SettlementCalculator {

    /// Computes each roster member's net position across all expenses.
    ///
    /// Every member of `roster` gets a balance, including those who come out
    /// exactly even — callers that only want non-zero entries can filter.
    /// Expenses referring to unknown participants are ignored rather than
    /// silently skewing the totals.
    ///
    /// - Parameters:
    ///   - expenses: The group's expenses.
    ///   - roster: Every current member of the group.
    /// - Returns: Balances ordered by amount, most owed first, with names
    ///   breaking ties so the result is stable.
    public static func balances(
        for expenses: [ExpenseEntry],
        roster: [Participant]
    ) -> [Balance] {
        let known = Dictionary(
            roster.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var net: [Participant.ID: Money] = known.keys.reduce(into: [:]) { result, id in
            result[id] = .zero
        }

        for expense in expenses {
            // Sorting makes the remainder distribution deterministic, so the
            // same inputs always produce the same cent-level result.
            let sharers = expense.sharedBetween
                .filter { known[$0] != nil }
                .sorted(by: precedes)

            guard known[expense.payer] != nil, !sharers.isEmpty else { continue }

            // The payer fronted the whole amount.
            net[expense.payer, default: .zero] += expense.amount

            // Each sharer owes their slice; slices sum to exactly `amount`.
            for (sharer, share) in zip(sharers, expense.amount.split(into: sharers.count)) {
                net[sharer, default: .zero] -= share
            }
        }

        return net
            .compactMap { id, amount in
                known[id].map { Balance(participant: $0, amount: amount) }
            }
            .sorted { lhs, rhs in
                lhs.amount == rhs.amount
                    ? lhs.participant.name < rhs.participant.name
                    : lhs.amount > rhs.amount
            }
    }

    /// Reduces balances to a short list of payments that settles the group.
    ///
    /// Greedy largest-debtor-pays-largest-creditor. This is not guaranteed to
    /// be the theoretical minimum — that problem is NP-hard — but it always
    /// settles in at most `n - 1` transfers, which is what matters in practice.
    ///
    /// - Precondition: balances should sum to zero, which holds for any set
    ///   produced by `balances(for:roster:)`.
    public static func transfers(settling balances: [Balance]) -> [Transfer] {
        var creditors = balances
            .filter { $0.amount > .zero }
            .map { (participant: $0.participant, remaining: $0.amount) }
        var debtors = balances
            .filter { $0.amount < .zero }
            .map { (participant: $0.participant, remaining: -$0.amount) }

        var transfers: [Transfer] = []

        while !creditors.isEmpty, !debtors.isEmpty {
            // Largest on each side, names breaking ties for determinism.
            let creditorIndex = indexOfLargest(in: creditors)
            let debtorIndex = indexOfLargest(in: debtors)

            let amount = min(creditors[creditorIndex].remaining, debtors[debtorIndex].remaining)
            guard amount > .zero else { break }

            transfers.append(Transfer(
                from: debtors[debtorIndex].participant,
                to: creditors[creditorIndex].participant,
                amount: amount
            ))

            creditors[creditorIndex].remaining -= amount
            debtors[debtorIndex].remaining -= amount

            if creditors[creditorIndex].remaining.isZero { creditors.remove(at: creditorIndex) }
            if debtors[debtorIndex].remaining.isZero { debtors.remove(at: debtorIndex) }
        }

        return transfers
    }

    /// Orders two ids by their raw bytes.
    ///
    /// This is the same total order as comparing `uuidString`: each byte is two
    /// hex digits at the same offset in both strings, and ASCII puts `0`–`9`
    /// before `A`–`F`, so no pair can compare differently. The split therefore
    /// hands the leftover cents to exactly the same people it always did —
    /// which is the point of sorting here at all, since two devices computing
    /// different remainders would disagree about who owes what.
    ///
    /// What changes is the cost: `uuidString` built and discarded a
    /// 36-character String on *every comparison*, in the loop that runs once
    /// per expense.
    private static func precedes(_ lhs: UUID, _ rhs: UUID) -> Bool {
        withUnsafeBytes(of: lhs.uuid) { left in
            withUnsafeBytes(of: rhs.uuid) { right in
                for index in left.indices where left[index] != right[index] {
                    return left[index] < right[index]
                }
                return false
            }
        }
    }

    private static func indexOfLargest(
        in entries: [(participant: Participant, remaining: Money)]
    ) -> Int {
        var best = 0
        for index in entries.indices where
            entries[index].remaining > entries[best].remaining
            || (entries[index].remaining == entries[best].remaining
                && entries[index].participant.name < entries[best].participant.name)
        {
            best = index
        }
        return best
    }
}

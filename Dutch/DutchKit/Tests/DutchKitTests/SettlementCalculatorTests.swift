import Foundation
import Testing
@testable import DutchKit

// MARK: - Fixtures

private enum Fixture {
    static let alice = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, name: "Alice")
    static let bob = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, name: "Bob")
    static let carol = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!, name: "Carol")
    static let dave = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!, name: "Dave")

    static func expense(
        _ amount: Int,
        paidBy payer: Participant,
        sharedBetween sharers: [Participant]
    ) -> ExpenseEntry {
        ExpenseEntry(
            id: UUID(),
            amount: Money(cents: amount),
            payer: payer.id,
            sharedBetween: Set(sharers.map(\.id))
        )
    }
}

private func amount(
    for participant: Participant,
    in balances: [Balance]
) -> Money? {
    balances.first { $0.participant.id == participant.id }?.amount
}

// MARK: - Balances

@Suite("Settlement balances")
struct SettlementBalanceTests {

    @Test("A shared expense splits between everyone who took part")
    func simpleSplit() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(3000, paidBy: Fixture.alice,
                                  sharedBetween: [Fixture.alice, Fixture.bob, Fixture.carol])],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol]
        )

        #expect(amount(for: Fixture.alice, in: balances) == Money(cents: 2000))
        #expect(amount(for: Fixture.bob, in: balances) == Money(cents: -1000))
        #expect(amount(for: Fixture.carol, in: balances) == Money(cents: -1000))
    }

    /// Regression: the payer used to be folded into the split unconditionally,
    /// so paying purely on someone else's behalf divided the bill one way too
    /// many. Alice pays for Bob and Carol only and should be owed all of it.
    @Test("A payer who did not take part is not charged a share")
    func payerNotAmongSharers() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(3000, paidBy: Fixture.alice,
                                  sharedBetween: [Fixture.bob, Fixture.carol])],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol]
        )

        #expect(amount(for: Fixture.alice, in: balances) == Money(cents: 3000))
        #expect(amount(for: Fixture.bob, in: balances) == Money(cents: -1500))
        #expect(amount(for: Fixture.carol, in: balances) == Money(cents: -1500))
    }

    /// Regression: the roster argument used to be ignored in favour of walking
    /// back through the first expense's relationships, so an empty expense list
    /// produced no balances at all.
    @Test("Members appear even when the group has no expenses")
    func rosterIsHonouredWithoutExpenses() {
        let balances = SettlementCalculator.balances(
            for: [],
            roster: [Fixture.alice, Fixture.bob]
        )

        let allZero = balances.allSatisfy { $0.amount.isZero }
        #expect(balances.count == 2)
        #expect(allZero)
    }

    @Test("A member who owes nothing still gets a balance")
    func uninvolvedMemberIncluded() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice,
                                  sharedBetween: [Fixture.alice, Fixture.bob])],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol]
        )

        #expect(amount(for: Fixture.carol, in: balances) == .zero)
    }

    @Test("Balances always sum to zero")
    func balancesReconcile() {
        let balances = SettlementCalculator.balances(
            for: [
                Fixture.expense(1000, paidBy: Fixture.alice,
                                sharedBetween: [Fixture.alice, Fixture.bob, Fixture.carol]),
                Fixture.expense(777, paidBy: Fixture.bob,
                                sharedBetween: [Fixture.bob, Fixture.carol]),
                Fixture.expense(31, paidBy: Fixture.carol,
                                sharedBetween: [Fixture.alice, Fixture.bob, Fixture.carol]),
            ],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol]
        )

        #expect(balances.reduce(Money.zero) { $0 + $1.amount } == .zero)
    }

    @Test("An expense nobody shares is ignored rather than skewing totals")
    func expenseWithNoSharers() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice, sharedBetween: [])],
            roster: [Fixture.alice, Fixture.bob]
        )

        let allZero = balances.allSatisfy { $0.amount.isZero }
        #expect(allZero)
    }

    @Test("Participants outside the roster do not distort the split")
    func unknownParticipantsIgnored() {
        let stranger = Participant(id: UUID(), name: "Stranger")
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice,
                                  sharedBetween: [Fixture.alice, Fixture.bob, stranger])],
            roster: [Fixture.alice, Fixture.bob]
        )

        // Split between the two known members only, not three ways.
        #expect(amount(for: Fixture.alice, in: balances) == Money(cents: 500))
        #expect(amount(for: Fixture.bob, in: balances) == Money(cents: -500))
        #expect(balances.reduce(Money.zero) { $0 + $1.amount } == .zero)
    }

    @Test("An indivisible amount still reconciles to the cent")
    func indivisibleAmount() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice,
                                  sharedBetween: [Fixture.alice, Fixture.bob, Fixture.carol])],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol]
        )

        #expect(balances.reduce(Money.zero) { $0 + $1.amount } == .zero)
        // 1000 / 3 = 334 + 333 + 333
        #expect(amount(for: Fixture.alice, in: balances) == Money(cents: 1000 - 334))
    }
}

// MARK: - Transfers

@Suite("Settlement transfers")
struct SettlementTransferTests {

    /// Regression: the greedy step used to take the *smallest* creditor and
    /// smallest debtor despite documenting the opposite, which produced a
    /// different — and needlessly long — payment list.
    @Test("The largest debt is settled first")
    func largestDebtFirst() {
        let balances = [
            Balance(participant: Fixture.alice, amount: Money(cents: 10000)),
            Balance(participant: Fixture.bob, amount: Money(cents: -6000)),
            Balance(participant: Fixture.carol, amount: Money(cents: -4000)),
        ]

        let transfers = SettlementCalculator.transfers(settling: balances)

        #expect(transfers.count == 2)
        #expect(transfers[0].from.id == Fixture.bob.id)
        #expect(transfers[0].amount == Money(cents: 6000))
        #expect(transfers[1].from.id == Fixture.carol.id)
        #expect(transfers[1].amount == Money(cents: 4000))
    }

    @Test("A two-person debt is one payment")
    func singleTransfer() {
        let transfers = SettlementCalculator.transfers(settling: [
            Balance(participant: Fixture.alice, amount: Money(cents: 7000)),
            Balance(participant: Fixture.bob, amount: Money(cents: -7000)),
        ])

        #expect(transfers.count == 1)
        #expect(transfers[0].from.id == Fixture.bob.id)
        #expect(transfers[0].to.id == Fixture.alice.id)
        #expect(transfers[0].amount == Money(cents: 7000))
    }

    @Test("A settled group needs no payments")
    func nothingToSettle() {
        #expect(SettlementCalculator.transfers(settling: []).isEmpty)
        #expect(SettlementCalculator.transfers(settling: [
            Balance(participant: Fixture.alice, amount: .zero),
            Balance(participant: Fixture.bob, amount: .zero),
        ]).isEmpty)
    }

    @Test("Transfers fully settle the group and stay within n-1 payments")
    func transfersSettleEverything() {
        let roster = [Fixture.alice, Fixture.bob, Fixture.carol, Fixture.dave]
        let balances = SettlementCalculator.balances(
            for: [
                Fixture.expense(5000, paidBy: Fixture.alice, sharedBetween: roster),
                Fixture.expense(1234, paidBy: Fixture.bob,
                                sharedBetween: [Fixture.bob, Fixture.carol]),
                Fixture.expense(99, paidBy: Fixture.dave, sharedBetween: roster),
                Fixture.expense(4321, paidBy: Fixture.carol,
                                sharedBetween: [Fixture.alice, Fixture.dave]),
            ],
            roster: roster
        )

        let transfers = SettlementCalculator.transfers(settling: balances)

        // Apply every payment and confirm nobody is left owing anything.
        var remaining = Dictionary(
            balances.map { ($0.participant.id, $0.amount) },
            uniquingKeysWith: { first, _ in first }
        )
        for transfer in transfers {
            remaining[transfer.from.id, default: .zero] += transfer.amount
            remaining[transfer.to.id, default: .zero] -= transfer.amount
        }

        let everyoneSettled = remaining.values.allSatisfy { $0.isZero }
        let allPositive = transfers.allSatisfy { $0.amount > .zero }
        let noSelfPayments = transfers.allSatisfy { $0.from.id != $0.to.id }

        #expect(everyoneSettled)
        #expect(transfers.count <= roster.count - 1)
        #expect(allPositive)
        #expect(noSelfPayments)
    }

    @Test("One debtor covering several creditors terminates cleanly")
    func oneDebtorManyCreditors() {
        let transfers = SettlementCalculator.transfers(settling: [
            Balance(participant: Fixture.alice, amount: Money(cents: 5000)),
            Balance(participant: Fixture.bob, amount: Money(cents: 3000)),
            Balance(participant: Fixture.carol, amount: Money(cents: -8000)),
        ])

        let allFromCarol = transfers.allSatisfy { $0.from.id == Fixture.carol.id }
        #expect(transfers.count == 2)
        #expect(allFromCarol)
        #expect(transfers.reduce(Money.zero) { $0 + $1.amount } == Money(cents: 8000))
    }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

// MARK: - Fixtures

private enum Fixture {
    static let alice = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, name: "Alice")
    static let bob = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, name: "Bob")
    static let carol = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!, name: "Carol")
    static let dave = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000D4")!, name: "Dave")
    static let eve = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E5")!, name: "Eve")
    static let frank = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000F6")!, name: "Frank")

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

    static func expense(
        _ amount: Int,
        paidBy payer: Participant,
        shares: [(Participant, Int)]
    ) -> ExpenseEntry {
        ExpenseEntry(
            id: UUID(),
            amount: Money(cents: amount),
            payer: payer.id,
            shares: Dictionary(uniqueKeysWithValues: shares.map { ($0.0.id, $0.1) })
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

// MARK: - Weighted splits

@Suite("Weighted splits")
struct WeightedSplitTests {

    /// The couple sharing a room against the person in a single.
    @Test("Shares divide an expense unevenly")
    func weightedSplit() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(9000, paidBy: Fixture.alice, shares: [
                (Fixture.alice, 2), (Fixture.bob, 1),
            ])],
            roster: [Fixture.alice, Fixture.bob]
        )

        // Alice owes two thirds of her own 90.00 bill, so she is owed the third
        // that is Bob's.
        #expect(amount(for: Fixture.alice, in: balances) == Money(cents: 3000))
        #expect(amount(for: Fixture.bob, in: balances) == Money(cents: -3000))
    }

    @Test("Weights are ratios, not absolute amounts")
    func weightsAreRelative() {
        let doubled = SettlementCalculator.balances(
            for: [Fixture.expense(9000, paidBy: Fixture.alice, shares: [
                (Fixture.alice, 4), (Fixture.bob, 2),
            ])],
            roster: [Fixture.alice, Fixture.bob]
        )

        #expect(amount(for: Fixture.alice, in: doubled) == Money(cents: 3000))
        #expect(amount(for: Fixture.bob, in: doubled) == Money(cents: -3000))
    }

    @Test("Equal weights are exactly an even split")
    func equalWeightsMatchEvenSplit() {
        let roster = [Fixture.alice, Fixture.bob, Fixture.carol]
        let even = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice, sharedBetween: roster)],
            roster: roster
        )
        let weighted = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice, shares: [
                (Fixture.alice, 1), (Fixture.bob, 1), (Fixture.carol, 1),
            ])],
            roster: roster
        )

        #expect(even == weighted)
    }

    @Test("A weighted split that doesn't divide evenly still reconciles")
    func weightedRemainderReconciles() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice, shares: [
                (Fixture.alice, 1), (Fixture.bob, 1), (Fixture.carol, 1), (Fixture.dave, 4),
            ])],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol, Fixture.dave]
        )

        #expect(balances.reduce(Money.zero) { $0 + $1.amount } == .zero)
        // 1000 in sevenths: Dave takes four of them.
        #expect(amount(for: Fixture.dave, in: balances) == Money(cents: -571))
    }

    /// The form previews each person's slice while the shares are being set,
    /// and it has to be the same number the balance lands on — a preview that
    /// is a cent out is worse than no preview at all.
    @Test("Slices match the balances they produce")
    func slicesAgreeWithBalances() {
        let shares = [Fixture.alice.id: 1, Fixture.bob.id: 1, Fixture.carol.id: 5]
        let amount = Money(cents: 1000)

        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.dave, shares: [
                (Fixture.alice, 1), (Fixture.bob, 1), (Fixture.carol, 5),
            ])],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol, Fixture.dave]
        )

        for (participant, slice) in SettlementCalculator.slices(of: amount, among: shares) {
            let charged = balances.first { $0.participant.id == participant }?.amount
            #expect(charged == -slice)
        }
    }

    @Test("Slices reconstruct the whole amount")
    func slicesReconcile() {
        let slices = SettlementCalculator.slices(
            of: Money(cents: 1000),
            among: [Fixture.alice.id: 1, Fixture.bob.id: 1, Fixture.carol.id: 1]
        )

        #expect(slices.count == 3)
        #expect(slices.reduce(Money.zero) { $0 + $1.amount } == Money(cents: 1000))
    }

    /// A zero weight drops the participant from the split rather than charging
    /// them nothing, so the rest of the bill still divides between the people
    /// who actually took part.
    @Test("A zero-weight participant is not in the split at all")
    func zeroWeightDropsOut() {
        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(1000, paidBy: Fixture.alice, shares: [
                (Fixture.alice, 1), (Fixture.bob, 1), (Fixture.carol, 0),
            ])],
            roster: [Fixture.alice, Fixture.bob, Fixture.carol]
        )

        #expect(amount(for: Fixture.alice, in: balances) == Money(cents: 500))
        #expect(amount(for: Fixture.bob, in: balances) == Money(cents: -500))
        #expect(amount(for: Fixture.carol, in: balances) == .zero)
    }
}

// MARK: - Real cases

/// The two splits the percentage control exists for, kept here as worked
/// examples. Both were done by hand on a calculator first; these pin the
/// answers so the arithmetic can't quietly drift away from them.
@Suite("Real cases")
struct RealCaseTests {

    /// Wrocław → Trzcińsko, 145.01 zł for six people, one of them on a
    /// student fare at 51% off. Everyone else pays a full share, so the
    /// weights are five hundreds and a forty-nine.
    @Test("A train ticket with one discounted fare")
    func discountedFare() {
        let full = Share.hundred
        let shares: [Participant.ID: Int] = [
            Fixture.alice.id: full, Fixture.bob.id: full, Fixture.carol.id: full,
            Fixture.dave.id: full, Fixture.eve.id: full,
            Fixture.frank.id: 49,
        ]

        let slices = SettlementCalculator.slices(of: Money(cents: 14501), among: shares)
        let byParticipant = Dictionary(
            slices.map { ($0.participant, $0.amount) },
            uniquingKeysWith: { first, _ in first }
        )

        // The student pays 12.94; the two stray grosze go to the largest
        // remainders, which here are the full fares.
        #expect(byParticipant[Fixture.frank.id] == Money(cents: 1294))
        #expect(byParticipant[Fixture.alice.id] == Money(cents: 2642))
        #expect(byParticipant[Fixture.bob.id] == Money(cents: 2642))
        #expect(byParticipant[Fixture.carol.id] == Money(cents: 2641))
        #expect(byParticipant[Fixture.dave.id] == Money(cents: 2641))
        #expect(byParticipant[Fixture.eve.id] == Money(cents: 2641))

        #expect(slices.reduce(Money.zero) { $0 + $1.amount } == Money(cents: 14501))
    }

    /// A hotel for six: two couples in two rooms, two people in singles. Four
    /// rooms, so four full shares — each half of a couple is 50%, and the four
    /// rooms come out at the same price.
    @Test("A hotel split between couples and singles")
    func couplesAndSingles() {
        let half = 50
        let full = Share.hundred
        let shares: [Participant.ID: Int] = [
            Fixture.alice.id: half, Fixture.bob.id: half,
            Fixture.carol.id: half, Fixture.dave.id: half,
            Fixture.eve.id: full, Fixture.frank.id: full,
        ]

        let slices = SettlementCalculator.slices(of: Money(cents: 80000), among: shares)
        let byParticipant = Dictionary(
            slices.map { ($0.participant, $0.amount) },
            uniquingKeysWith: { first, _ in first }
        )

        // 800.00 over four rooms is 200.00 a room, however many people are in it.
        #expect(byParticipant[Fixture.alice.id] == Money(cents: 10000))
        #expect(byParticipant[Fixture.bob.id] == Money(cents: 10000))
        #expect(byParticipant[Fixture.eve.id] == Money(cents: 20000))
        #expect(byParticipant[Fixture.frank.id] == Money(cents: 20000))

        let firstRoom = (byParticipant[Fixture.alice.id] ?? .zero) + (byParticipant[Fixture.bob.id] ?? .zero)
        #expect(firstRoom == byParticipant[Fixture.eve.id])
        #expect(slices.reduce(Money.zero) { $0 + $1.amount } == Money(cents: 80000))
    }

    /// Percentages are relative, so the same split can be written with any
    /// scale. This is what lets the form store "everyone at 100%" as no
    /// weighting at all.
    @Test("A full share is whatever number every share agrees on")
    func scaleIsArbitrary() {
        let asPercent = SettlementCalculator.slices(
            of: Money(cents: 9000),
            among: [Fixture.alice.id: 100, Fixture.bob.id: 50]
        )
        let asShares = SettlementCalculator.slices(
            of: Money(cents: 9000),
            among: [Fixture.alice.id: 2, Fixture.bob.id: 1]
        )

        #expect(asPercent.map(\.amount) == asShares.map(\.amount))
        #expect(asPercent.map(\.amount) == [Money(cents: 6000), Money(cents: 3000)])
    }

    private enum Share {
        /// Spelled out rather than written as a bare `100` at every call site,
        /// so the examples read as "a full share" and not as a magic number.
        static let hundred = 100
    }
}

// MARK: - Reimbursements

/// A payment between two people is not a special case in the calculator: it is
/// an expense paid by the debtor and shared by the creditor alone. These pin
/// that down, because the whole design of `GroupStore.recordPayment` rests on
/// it staying true.
@Suite("Reimbursements")
struct ReimbursementTests {

    @Test("Paying what you owe settles the group")
    func paymentSettlesDebt() {
        let dinner = Fixture.expense(3000, paidBy: Fixture.alice,
                                     sharedBetween: [Fixture.alice, Fixture.bob])
        // Bob owes 15.00 and hands it over: he is the payer, Alice the sharer.
        let payback = Fixture.expense(1500, paidBy: Fixture.bob, sharedBetween: [Fixture.alice])

        let balances = SettlementCalculator.balances(
            for: [dinner, payback],
            roster: [Fixture.alice, Fixture.bob]
        )

        let allZero = balances.allSatisfy { $0.amount.isZero }
        #expect(allZero)
        #expect(SettlementCalculator.transfers(settling: balances).isEmpty)
    }

    @Test("A partial payment leaves the remainder owing")
    func partialPayment() {
        let balances = SettlementCalculator.balances(
            for: [
                Fixture.expense(3000, paidBy: Fixture.alice,
                                sharedBetween: [Fixture.alice, Fixture.bob]),
                Fixture.expense(500, paidBy: Fixture.bob, sharedBetween: [Fixture.alice]),
            ],
            roster: [Fixture.alice, Fixture.bob]
        )

        #expect(amount(for: Fixture.bob, in: balances) == Money(cents: -1000))

        let transfers = SettlementCalculator.transfers(settling: balances)
        #expect(transfers.count == 1)
        #expect(transfers[0].from.id == Fixture.bob.id)
        #expect(transfers[0].amount == Money(cents: 1000))
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

// MARK: - Remainder ordering

/// The leftover minor units of an uneven split go to the earliest sharers by
/// id, and "earliest" has to keep meaning the same thing on every device and
/// across every release — two devices that disagree about the order disagree
/// about who owes the extra cent, and the balances stop reconciling.
@Suite("Remainder ordering")
struct RemainderOrderingTests {

    @Test("The extra cent goes to whichever id sorts first as a string")
    func remainderFollowsUUIDStringOrder() {
        for _ in 0 ..< 500 {
            let first = Participant(id: UUID(), name: "First")
            let second = Participant(id: UUID(), name: "Second")
            let payer = Participant(id: UUID(), name: "Payer")

            let balances = SettlementCalculator.balances(
                for: [Fixture.expense(101, paidBy: payer, sharedBetween: [first, second])],
                roster: [first, second, payer]
            )

            // 101 split two ways is 51 and 50, charged as negative balances.
            let earlier = first.id.uuidString < second.id.uuidString ? first : second
            let later = earlier.id == first.id ? second : first

            #expect(amount(for: earlier, in: balances) == Money(cents: -51))
            #expect(amount(for: later, in: balances) == Money(cents: -50))
        }
    }

    @Test("Ordering holds across the digit-to-letter boundary in each byte")
    func remainderAcrossHexBoundary() {
        // Ids chosen so the sharers arrive out of order and the deciding byte
        // straddles `9`/`A`, where a byte comparison and a hex-string
        // comparison would diverge if the two orders were not equivalent.
        let high = Participant(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000000")!, name: "High")
        let low = Participant(id: UUID(uuidString: "9F000000-0000-0000-0000-000000000000")!, name: "Low")
        let payer = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Payer")

        let balances = SettlementCalculator.balances(
            for: [Fixture.expense(101, paidBy: payer, sharedBetween: [high, low])],
            roster: [high, low, payer]
        )

        #expect(amount(for: low, in: balances) == Money(cents: -51))
        #expect(amount(for: high, in: balances) == Money(cents: -50))
    }
}

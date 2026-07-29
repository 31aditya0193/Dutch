/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Testing
@testable import DutchKit

@Suite("Money")
struct MoneyTests {

    @Test("Major-unit input converts to cents without drift")
    func conversionFromDouble() {
        #expect(Money(amount: 12.34).cents == 1234)
        #expect(Money(amount: 0.1).cents == 10)
        #expect(Money(amount: 0.07).cents == 7)
        #expect(Money(amount: 45.00).cents == 4500)
    }

    /// Half-cent inputs cannot round-trip, and which way they fall depends on
    /// where the binary `Double` actually lands: `1.005` is really `1.00499…`
    /// so it rounds down, while `0.005` is really `0.00500…04` so it rounds up.
    /// Routing through `Decimal` gives identical results — the precision is
    /// gone before `Money` ever sees the value. Callers needing exactness at
    /// this scale should build `Money(cents:)` directly.
    @Test("Sub-cent precision is lost at the Double boundary, not silently faked")
    func subCentInputIsNotRepresentable() {
        #expect(Money(amount: 1.005).cents == 100)
        #expect(Money(amount: 0.005).cents == 1)
    }

    @Test("Round trip back to major units")
    func conversionToDouble() {
        #expect(Money(cents: 1234).amount == 12.34)
        #expect(Money(cents: 0).amount == 0)
    }

    @Test("An even split loses nothing")
    func evenSplit() {
        let shares = Money(cents: 900).split(into: 3)
        #expect(shares == [Money(cents: 300), Money(cents: 300), Money(cents: 300)])
    }

    @Test("An uneven split distributes the remainder instead of dropping it")
    func unevenSplit() {
        let shares = Money(cents: 100).split(into: 3)
        #expect(shares == [Money(cents: 34), Money(cents: 33), Money(cents: 33)])
        #expect(shares.reduce(Money.zero, +) == Money(cents: 100))
    }

    @Test("Every split reconciles exactly", arguments: [
        (1, 1), (100, 3), (1000, 7), (1, 3), (9999, 11), (5, 4), (0, 3),
    ])
    func splitAlwaysReconciles(cents: Int, count: Int) {
        let total = Money(cents: cents)
        let shares = total.split(into: count)
        #expect(shares.count == count)
        #expect(shares.reduce(Money.zero, +) == total)
    }

    @Test("Negative amounts reconcile too")
    func negativeSplit() {
        let total = Money(cents: -100)
        let shares = total.split(into: 3)
        #expect(shares.reduce(Money.zero, +) == total)
        #expect(shares == [Money(cents: -34), Money(cents: -33), Money(cents: -33)])
    }

    @Test("Splitting into a non-positive number of shares yields nothing")
    func degenerateSplit() {
        #expect(Money(cents: 100).split(into: 0).isEmpty)
        #expect(Money(cents: 100).split(into: -2).isEmpty)
    }

    // MARK: - Weighted splits

    @Test("Weights divide the amount in proportion")
    func weightedSplit() {
        #expect(Money(cents: 3000).split(among: [2, 1]) == [Money(cents: 2000), Money(cents: 1000)])
        #expect(
            Money(cents: 6000).split(among: [1, 2, 3])
                == [Money(cents: 1000), Money(cents: 2000), Money(cents: 3000)]
        )
    }

    /// The room two people share against the single: `[2, 1]` of 10.00 is
    /// 6.67 / 3.33, and the stray cent has to land somewhere rather than
    /// disappear.
    @Test("An uneven weighted split still reconciles to the cent")
    func weightedSplitRemainder() {
        let shares = Money(cents: 1000).split(among: [2, 1])
        #expect(shares == [Money(cents: 667), Money(cents: 333)])
        #expect(shares.reduce(Money.zero, +) == Money(cents: 1000))
    }

    /// The leftover goes to the largest fractional remainder, not to whoever
    /// happens to be first: weight 2 is short by 2/3 of a cent here and weight
    /// 1 by 1/3, so the extra cent belongs to the larger share.
    @Test("Leftover minor units follow the largest remainder")
    func weightedSplitFavoursLargestRemainder() {
        #expect(Money(cents: 100).split(among: [1, 2]) == [Money(cents: 33), Money(cents: 67)])
    }

    /// An even split is not a special case in the code — `split(into:)` is
    /// `split(among:)` with equal weights, and equal remainders tie-break to
    /// the earliest share, which is the behaviour that always shipped.
    @Test("Equal weights reproduce an even split exactly")
    func equalWeightsMatchEvenSplit() {
        #expect(Money(cents: 100).split(among: [1, 1, 1]) == Money(cents: 100).split(into: 3))
        #expect(Money(cents: 100).split(among: [1, 1, 1]) == [Money(cents: 34), Money(cents: 33), Money(cents: 33)])
        // Relative, not absolute: doubling every weight changes nothing.
        #expect(Money(cents: 100).split(among: [2, 2, 2]) == Money(cents: 100).split(into: 3))
    }

    @Test("Every weighted split reconciles exactly", arguments: [
        (100, [1, 2]), (1000, [2, 1]), (1, [1, 1, 1]), (9999, [3, 5, 7]),
        (0, [1, 4]), (12345, [1, 1, 1, 1, 1, 1, 7]), (5, [4]),
    ])
    func weightedSplitAlwaysReconciles(cents: Int, weights: [Int]) {
        let total = Money(cents: cents)
        let shares = total.split(among: weights)
        #expect(shares.count == weights.count)
        #expect(shares.reduce(Money.zero, +) == total)
    }

    @Test("Negative weighted amounts reconcile too")
    func negativeWeightedSplit() {
        let total = Money(cents: -1000)
        let shares = total.split(among: [2, 1])
        #expect(shares == [Money(cents: -667), Money(cents: -333)])
        #expect(shares.reduce(Money.zero, +) == total)
    }

    /// A zero or negative weight is a caller mistake, not a participant who
    /// owes nothing — pricing them at zero would hide it behind a bill that
    /// still adds up.
    @Test("Non-positive weights yield nothing")
    func degenerateWeightedSplit() {
        #expect(Money(cents: 100).split(among: []).isEmpty)
        #expect(Money(cents: 100).split(among: [1, 0]).isEmpty)
        #expect(Money(cents: 100).split(among: [2, -1]).isEmpty)
    }
}

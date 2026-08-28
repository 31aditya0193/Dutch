/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

@Suite("Tip rates")
struct TipRateTests {

    @Test("No tip leaves the amount exactly as entered")
    func noneIsIdentity() {
        #expect(TipRate.none.applied(to: 47.30) == 47.30)
        #expect(TipRate.none.isNone)
    }

    /// Asserted through `Money`, not on the raw `Double`. What the app stores
    /// is cents, and a tip is floating-point arithmetic — comparing the
    /// intermediate directly would be testing the last bit of a `Double`
    /// rather than the behaviour anybody depends on.
    @Test("A percentage is added on top")
    func addsPercentage() throws {
        let tip = try #require(TipRate(percent: 15))
        #expect(Money(amount: tip.applied(to: 100)) == Money(cents: 11_500))
        #expect(Money(amount: tip.applied(to: 47.35)) == Money(cents: 5_445))
    }

    @Test("Fractional percentages work, because 12.5% is a real service charge")
    func fractionalPercent() throws {
        let tip = try #require(TipRate(percent: 12.5))
        #expect(Money(amount: tip.applied(to: 80)) == Money(cents: 9_000))
    }

    @Test("Zero is a valid rate and adds nothing")
    func zeroIsValid() throws {
        let tip = try #require(TipRate(percent: 0))
        #expect(tip.isNone)
        #expect(tip.applied(to: 12.34) == 12.34)
    }

    @Test("A negative percentage is refused — a discount is not a tip")
    func rejectsNegative() {
        #expect(TipRate(percent: -1) == nil)
        #expect(TipRate(percent: -0.5) == nil)
    }

    @Test("A percentage past the cap is refused, catching a missed decimal point")
    func rejectsAboveCap() {
        #expect(TipRate(percent: 1500) == nil)
        #expect(TipRate(percent: TipRate.maximumPercent) != nil)
        #expect(TipRate(percent: TipRate.maximumPercent + 0.01) == nil)
    }

    @Test("Non-finite input is refused rather than trapping downstream")
    func rejectsNonFinite() {
        #expect(TipRate(percent: .nan) == nil)
        #expect(TipRate(percent: .infinity) == nil)
    }

    /// The reason `applied(to:)` takes a `Double`: rounding stays in one place,
    /// so a tipped bill still splits without losing a cent.
    @Test("A tipped bill still splits back to its own total")
    func tippedBillSplitsExactly() throws {
        let tip = try #require(TipRate(percent: 15))
        let total = Money(amount: tip.applied(to: 47.35))

        let shares = total.split(into: 3)
        #expect(shares.reduce(Money.zero, +) == total)
    }

    @Test("Tipping happens in the currency paid, then converts once")
    func tipAppliesBeforeConversion() throws {
        let tip = try #require(TipRate(percent: 10))
        // 1 500 HUF plus 10% is 1 650 HUF, at 389.15 HUF to the euro.
        let foreign = try #require(
            ForeignAmount(amount: tip.applied(to: 1500), currencyCode: "HUF", rate: 389.15)
        )
        #expect(Money(amount: foreign.amount) == Money(cents: 165_000))
        #expect(foreign.converted == Money(amount: 1650 / 389.15))
    }
}

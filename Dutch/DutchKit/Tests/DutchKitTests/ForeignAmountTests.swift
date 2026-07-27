import Testing
@testable import DutchKit

@Suite("ForeignAmount")
struct ForeignAmountTests {

    @Test("Converts by dividing by the rate")
    func conversion() {
        let dinner = ForeignAmount(amount: 198.50, currencyCode: "PLN", rate: 4.4111)
        // 198.50 / 4.4111 = 45.0001…, so the stored euro amount is 45.00.
        #expect(dinner?.converted == Money(cents: 4500))
    }

    /// The direction is the whole point: a rate above 1 means the foreign
    /// currency is the weaker one, so the converted amount must come out
    /// *smaller*. Multiplying instead of dividing passes every symmetric test
    /// and is wrong by a factor of `rate²`.
    @Test("A weaker foreign currency converts down, not up")
    func conversionDirection() {
        let paid = ForeignAmount(amount: 400, currencyCode: "PLN", rate: 4.0)
        #expect(paid?.converted == Money(cents: 10_000))
    }

    @Test("A rate below 1 converts up")
    func strongerForeignCurrency() {
        // A group in USD paying 50 GBP at 0.80 GBP per USD owes $62.50.
        let paid = ForeignAmount(amount: 50, currencyCode: "GBP", rate: 0.8)
        #expect(paid?.converted == Money(cents: 6250))
    }

    /// `amount / 0` is infinity, and `Money`'s `Int` conversion traps on it.
    /// A zero rate is one keystroke away in a text field, so this has to fail
    /// as a value rather than as a crash.
    @Test("Unusable rates fail construction instead of trapping")
    func rejectsUnusableRates() {
        #expect(ForeignAmount(amount: 100, currencyCode: "PLN", rate: 0) == nil)
        #expect(ForeignAmount(amount: 100, currencyCode: "PLN", rate: -4.4) == nil)
        #expect(ForeignAmount(amount: 100, currencyCode: "PLN", rate: .infinity) == nil)
        #expect(ForeignAmount(amount: .infinity, currencyCode: "PLN", rate: 4.4) == nil)
        #expect(ForeignAmount(amount: .nan, currencyCode: "PLN", rate: 4.4) == nil)
    }

    @Test("A zero expense is legal")
    func zeroIsAllowed() {
        #expect(ForeignAmount(amount: 0, currencyCode: "PLN", rate: 4.4111)?.converted == .zero)
    }

    /// Currencies without a minor unit are the reason `amount` is not a
    /// `Money`. 5000 forint is five thousand forint, not fifty.
    @Test("Zero-decimal currencies keep their magnitude")
    func zeroDecimalCurrencies() {
        let paid = ForeignAmount(amount: 5000, currencyCode: "HUF", rate: 400)
        #expect(paid?.amount == 5000)
        #expect(paid?.converted == Money(cents: 1250))
    }

    /// The rounding happens once, here, so that the amount the group stores is
    /// a fixed fact. Everything downstream splits that integer.
    @Test("Conversion rounds to minor units once")
    func roundsOnce() {
        let paid = ForeignAmount(amount: 10, currencyCode: "PLN", rate: 3)
        // 3.333… rounds to 3.33, and three shares of it sum back exactly.
        #expect(paid?.converted == Money(cents: 333))
        #expect(paid?.converted.split(into: 3).reduce(Money.zero, +) == Money(cents: 333))
    }
}

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
}

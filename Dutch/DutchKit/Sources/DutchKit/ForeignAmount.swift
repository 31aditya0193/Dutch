import Foundation

/// An amount as it was actually paid, in a currency other than the one its
/// group settles in — a dinner bought for 198.50 zł by a group keeping its
/// books in euros.
///
/// This type exists to convert *once*, at the moment the expense is recorded,
/// and then never again. A group's balances have to stay put: if the app
/// re-converted at display time, every debt in a shared trip would drift a
/// little each day as the rate moved, and an expense somebody already settled
/// would quietly reopen. So the rate is captured here, the result is stored as
/// an ordinary amount in the group's own currency, and this value survives only
/// as provenance for the row that shows it.
public struct ForeignAmount: Hashable, Sendable {
    /// The amount in `currencyCode`, in major units — 198.50, not 19850.
    ///
    /// Not a `Money`, deliberately. `Money` is a two-decimal type, and a third
    /// of the currencies someone might pay in are not: 5000 HUF and 500 JPY
    /// have no minor unit at all, and pushing them through cents would render
    /// them a hundred times too small. Held as written and formatted by
    /// Foundation, which knows each currency's fraction digits.
    public let amount: Double

    /// ISO 4217 code of the currency actually paid in.
    public let currencyCode: String

    /// How many units of `currencyCode` one unit of the *group's* currency buys
    /// — 4.4111 for a group in EUR paying in PLN.
    ///
    /// This direction, and not its reciprocal, because it is the one written on
    /// exchange boards and returned by a search for "EUR to PLN", so it is the
    /// number a person can check at a glance. It also means the conversion
    /// divides rather than multiplies, which is the easy thing to get backwards
    /// — hence `converted`, so no call site has to remember.
    public let rate: Double

    /// Fails rather than trapping on a rate that cannot convert anything.
    ///
    /// A zero rate is one keystroke away in a text field, and `amount / 0` is
    /// infinity, which traps on the way into `Money`'s `Int` conversion. The
    /// form treats `nil` here as "not valid yet" and leaves Save disabled.
    public init?(amount: Double, currencyCode: String, rate: Double) {
        guard rate > 0, rate.isFinite, amount.isFinite, amount >= 0 else { return nil }

        self.amount = amount
        self.currencyCode = currencyCode
        self.rate = rate
    }

    /// The equivalent in the group's currency, rounded to minor units exactly
    /// once.
    ///
    /// Whatever this returns is what gets stored and what every later balance
    /// is built from. Rounding here and only here is what keeps
    /// `Money.split`'s promise that shares sum back to the total.
    public var converted: Money {
        Money(amount: amount / rate)
    }

    /// Formatted in the currency it was paid in — `198,50 zł`, `5000 Ft`.
    public func formatted() -> String {
        amount.formatted(.currency(code: currencyCode))
    }
}

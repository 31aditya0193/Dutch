import Foundation

/// A monetary amount held as a whole number of minor units (cents).
///
/// Splitting a bill three ways is the canonical way to lose a cent to
/// floating point. Keeping money as an integer makes every split exact
/// and lets `SettlementCalculator` guarantee that the shares of an
/// expense sum back to the original amount.
public struct Money: Hashable, Sendable, Comparable, AdditiveArithmetic {
    /// The amount in minor units — cents for USD/EUR, and so on.
    public let cents: Int

    public init(cents: Int) {
        self.cents = cents
    }

    /// Converts a user-entered major-unit value (e.g. `12.34`) to cents,
    /// rounding half away from zero the way a cash register would.
    public init(amount: Double) {
        self.cents = Int((amount * 100).rounded())
    }

    /// The major-unit value, for display and currency formatting.
    public var amount: Double {
        Double(cents) / 100
    }

    public var isZero: Bool { cents == 0 }
    public var magnitude: Money { Money(cents: abs(cents)) }

    // MARK: - Arithmetic

    public static let zero = Money(cents: 0)

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents + rhs.cents)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        Money(cents: lhs.cents - rhs.cents)
    }

    public static prefix func - (value: Money) -> Money {
        Money(cents: -value.cents)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.cents < rhs.cents
    }

    // MARK: - Splitting

    /// Divides the amount into `count` shares that sum back to exactly `self`.
    ///
    /// When the amount doesn't divide evenly the leftover minor units are
    /// handed to the earliest shares, so `Money(cents: 100).split(into: 3)`
    /// yields `[34, 33, 33]` rather than three lossy `33.33`s.
    public func split(into count: Int) -> [Money] {
        guard count > 0 else { return [] }

        let base = cents / count
        let remainder = abs(cents % count)
        let step = cents < 0 ? -1 : 1

        return (0 ..< count).map { index in
            Money(cents: base + (index < remainder ? step : 0))
        }
    }
}

// MARK: - Formatting

extension Money {
    /// Formats using the given currency code, defaulting to the user's locale.
    public func formatted(currencyCode: String? = nil) -> String {
        let code = currencyCode
            ?? Locale.current.currency?.identifier
            ?? "USD"
        return amount.formatted(.currency(code: code))
    }
}

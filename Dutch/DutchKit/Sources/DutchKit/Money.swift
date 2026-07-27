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

    /// Divides the amount into `count` equal shares that sum back to exactly
    /// `self`.
    ///
    /// When the amount doesn't divide evenly the leftover minor units are
    /// handed to the earliest shares, so `Money(cents: 100).split(into: 3)`
    /// yields `[34, 33, 33]` rather than three lossy `33.33`s.
    public func split(into count: Int) -> [Money] {
        guard count > 0 else { return [] }
        return split(among: Array(repeating: 1, count: count))
    }

    /// Divides the amount in proportion to `weights`, summing back to exactly
    /// `self`.
    ///
    /// Relative weights, not exact amounts. `[2, 1]` and `[100, 50]` mean the
    /// same thing — the app passes percentages of a full share, so a train
    /// ticket with one 51%-off fare is `[100, 100, 100, 100, 100, 49]` and two
    /// couples sharing rooms against two people in singles is
    /// `[50, 50, 50, 50, 100, 100]`. Integers keep the split exact: there is no
    /// step where a percentage of a cent has to go somewhere, and the parts
    /// reconstruct the whole exactly as they do in `split(into:)`.
    ///
    /// Leftover minor units go to the shares with the largest fractional
    /// remainder, ties broken by position. For equal weights every remainder is
    /// identical, so this degenerates to exactly the earliest-first behaviour
    /// of `split(into:)` — the two are one algorithm, and an even split is not
    /// a special case of the code.
    ///
    /// Returns `[]` for an empty list or any non-positive weight: a zero share
    /// is not a participant who owes nothing, it is someone who does not belong
    /// in the split at all, and silently pricing them at zero would hide a
    /// caller's mistake behind a plausible-looking bill.
    public func split(among weights: [Int]) -> [Money] {
        guard !weights.isEmpty, weights.allSatisfy({ $0 > 0 }) else { return [] }

        let total = weights.reduce(0, +)

        // Truncating division, so every quotient falls short by its remainder
        // and the shortfall is redistributed below rather than dropped.
        let quotients = weights.map { cents * $0 / total }
        let remainders = weights.map { abs(cents * $0 % total) }

        // Same sign as `cents`, and strictly smaller in magnitude than the
        // number of shares, so at most one unit is handed to each.
        var leftover = abs(cents - quotients.reduce(0, +))
        let step = cents < 0 ? -1 : 1

        var shares = quotients
        for index in remainders.indices
            .sorted(by: { remainders[$0] == remainders[$1] ? $0 < $1 : remainders[$0] > remainders[$1] })
        where leftover > 0 {
            shares[index] += step
            leftover -= 1
        }

        return shares.map(Money.init(cents:))
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

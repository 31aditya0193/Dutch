/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// A tip, tax or service charge, as a percentage added on top of an entered
/// amount before it is split.
///
/// One percentage rather than three named ones, deliberately. The moment there
/// is a separate tip and a separate tax, somebody has to answer whether the tip
/// is computed on the pre-tax or the post-tax total — a question real people
/// argue about at real tables, and this app exists to delete that arithmetic
/// rather than to host it. A single figure covers a European service charge, a
/// UK discretionary 12.5% and a US tip, and anyone who wants two of them can
/// add them together or simply type the final total.
///
/// Held as a percentage — 15 for 15%, never 0.15 — because that is what is
/// printed on the receipt and what the person is copying from. The conversion
/// happens once, in `applied(to:)`.
public struct TipRate: Hashable, Sendable {

    /// The percentage added on top. Always in `0...maximumPercent`.
    public let percent: Double

    /// No tip, and the default everywhere. `applied(to:)` returns its argument.
    public static let none = TipRate(unchecked: 0)

    /// The largest tip that can be entered.
    ///
    /// A cap exists because the failure it prevents is silent: a decimal point
    /// missed in a text field turns a 15% tip into 1500% and a 47.30 dinner
    /// into 756.80, which is a plausible-looking number that nobody notices
    /// until the balances are wrong. Doubling a bill is already beyond any real
    /// service charge, so anyone who genuinely means it can type the amount.
    public static let maximumPercent: Double = 100

    /// Fails rather than clamping, so the form can treat it as "not valid yet"
    /// and leave Save alone — the same contract `ForeignAmount.init` has.
    ///
    /// Negative is rejected on purpose and is not an oversight. A percentage
    /// that reduces the bill is a *discount*, which is a different feature
    /// wearing this one's control, and accepting it here would let a mistyped
    /// minus sign quietly lower a total that everybody else is splitting.
    public init?(percent: Double) {
        guard percent.isFinite, percent >= 0, percent <= Self.maximumPercent else {
            return nil
        }
        self.percent = percent
    }

    private init(unchecked percent: Double) {
        self.percent = percent
    }

    /// Whether this adds anything, for call sites deciding whether to mention it.
    public var isNone: Bool { percent == 0 }

    /// The amount with the tip added.
    ///
    /// Takes and returns a `Double` in major units rather than a `Money`, and
    /// that is the whole reason this type is safe to use. The amount an expense
    /// stores is rounded to minor units exactly once — in `Money.init(amount:)`
    /// for an ordinary expense, or in `ForeignAmount.converted` for one paid
    /// abroad — and that single rounding is what keeps `Money.split`'s promise
    /// that the shares add back up to the total. Scaling a `Money` instead
    /// would round a second time, and a three-way split of a tipped bill could
    /// then miss it by a cent.
    ///
    /// So this multiplies the figure as typed, before either of those, and adds
    /// no rounding point of its own.
    ///
    /// Written as an added share rather than as `amount * (1 + percent / 100)`,
    /// which is the same arithmetic and measurably worse at it: the factor
    /// `1.15` has no exact binary representation, so that spelling turns a 15%
    /// tip on 100 into 114.99999999999999. Multiplying before dividing keeps
    /// the common cases — whole percentages of whole amounts — exact. It is
    /// still floating point and still not exact in general, which is why
    /// nothing downstream compares these values directly; they go into `Money`
    /// and are compared there.
    public func applied(to amount: Double) -> Double {
        amount + amount * percent / 100
    }
}

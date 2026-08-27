/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// Every word `GroupSummary.text(locale:strings:)` puts in the message, supplied
/// by the caller.
///
/// The summary is the one place in DutchKit that writes prose rather than
/// numbers, and prose has to be translated. Reaching for `String(localized:)`
/// here would mean giving the package a string catalog and a resource bundle of
/// its own — a second place for translations to live, findable only by whoever
/// already knows the package exists. Instead the app resolves the wording
/// against the single catalog it already ships and hands the result over, which
/// keeps DutchKit what it is: Foundation, no resources, tests that run in a
/// second without a simulator.
///
/// The members that take arguments are closures rather than format strings on
/// purpose. A closure lets the caller reach for `String(localized:)`, so plural
/// agreement and word order come from the catalog — a language that says "Ann
/// pays €20.00 to Ben", or that needs four plural forms where English needs two,
/// is a catalog entry rather than a change here.
///
/// `english` is the default everywhere, so a caller with nothing to say about
/// language — the tests, a script, a future command-line tool — gets exactly
/// what this type used to hardcode.
public struct GroupSummaryStrings: Sendable {

    /// Stands in for a group saved without a name.
    public var fallbackTitle: String

    /// Stands in for an expense saved without a title.
    public var untitled: String

    /// The headline for a group that has members but has spent nothing.
    public var noExpensesYet: String

    /// Heading over the list of payments that would settle the group.
    public var settleUpHeading: String

    /// Heading over the expense log.
    public var expensesHeading: String

    /// Said when the payments have all been made.
    public var everyoneSettled: String

    /// Said when there is nothing to settle because nothing has been spent —
    /// deliberately not the same sentence as `everyoneSettled`.
    public var nothingToSettle: String

    /// How much the group has spent, given the already-formatted amount.
    public var total: @Sendable (String) -> String

    /// How many expenses the total is made of.
    public var expenseCount: @Sendable (Int) -> String

    /// How many people are in the group.
    public var peopleCount: @Sendable (Int) -> String

    /// One line of the settle-up list: who pays whom, and how much.
    public var transferLine: @Sendable (_ from: String, _ to: String, _ amount: String) -> String

    /// One log line for money that moved between two people and bought nothing.
    public var reimbursementLine: @Sendable (_ payer: String, _ to: String, _ amount: String) -> String

    /// One log line for something the group bought.
    public var expenseLine: @Sendable (_ title: String, _ amount: String, _ payer: String) -> String

    /// The same line for an expense paid in another currency, with what was
    /// actually handed over at the till.
    public var foreignExpenseLine: @Sendable (
        _ title: String, _ amount: String, _ foreign: String, _ payer: String
    ) -> String

    /// Adds the date to a finished log line. Separate from the line itself
    /// because the date is optional — an expense saved without one still gets a
    /// line, it just ends earlier.
    public var dated: @Sendable (_ line: String, _ date: String) -> String

    public init(
        fallbackTitle: String,
        untitled: String,
        noExpensesYet: String,
        settleUpHeading: String,
        expensesHeading: String,
        everyoneSettled: String,
        nothingToSettle: String,
        total: @escaping @Sendable (String) -> String,
        expenseCount: @escaping @Sendable (Int) -> String,
        peopleCount: @escaping @Sendable (Int) -> String,
        transferLine: @escaping @Sendable (String, String, String) -> String,
        reimbursementLine: @escaping @Sendable (String, String, String) -> String,
        expenseLine: @escaping @Sendable (String, String, String) -> String,
        foreignExpenseLine: @escaping @Sendable (String, String, String, String) -> String,
        dated: @escaping @Sendable (String, String) -> String
    ) {
        self.fallbackTitle = fallbackTitle
        self.untitled = untitled
        self.noExpensesYet = noExpensesYet
        self.settleUpHeading = settleUpHeading
        self.expensesHeading = expensesHeading
        self.everyoneSettled = everyoneSettled
        self.nothingToSettle = nothingToSettle
        self.total = total
        self.expenseCount = expenseCount
        self.peopleCount = peopleCount
        self.transferLine = transferLine
        self.reimbursementLine = reimbursementLine
        self.expenseLine = expenseLine
        self.foreignExpenseLine = foreignExpenseLine
        self.dated = dated
    }
}

extension GroupSummaryStrings {

    /// The wording the summary shipped with, and the default for every caller
    /// that doesn't localize.
    public static let english = GroupSummaryStrings(
        fallbackTitle: "Group",
        untitled: "Untitled",
        noExpensesYet: "No expenses yet",
        settleUpHeading: "Settle up",
        expensesHeading: "Expenses",
        everyoneSettled: "Everyone is settled up.",
        nothingToSettle: "Nothing to settle yet.",
        total: { "\($0) total" },
        expenseCount: { "\($0) \($0 == 1 ? "expense" : "expenses")" },
        peopleCount: { "\($0) \($0 == 1 ? "person" : "people")" },
        transferLine: { from, to, amount in "• \(from) pays \(to) \(amount)" },
        reimbursementLine: { payer, to, amount in "• \(payer) paid \(to) \(amount)" },
        expenseLine: { title, amount, payer in "• \(title) — \(amount), paid by \(payer)" },
        foreignExpenseLine: { title, amount, foreign, payer in
            "• \(title) — \(amount) (\(foreign)), paid by \(payer)"
        },
        dated: { line, date in "\(line) — \(date)" }
    )
}

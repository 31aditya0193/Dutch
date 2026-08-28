/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import DutchKit
import Foundation

extension GroupSummaryStrings {

    /// The shareable summary in the reader's language.
    ///
    /// `GroupSummary` renders the message but owns none of its words — see
    /// `GroupSummaryStrings` for why. This is the other half: the app looks
    /// every line up in the one string catalog it already ships, so a new
    /// language is a column there rather than an edit here or in the package.
    ///
    /// The literals below are keys, exactly as `Text("Settings")` is a key
    /// elsewhere in the app. Word order and plural agreement travel with the
    /// translation — `transferLine` may put the amount before either name, and
    /// the counts take as many plural forms as the language needs.
    ///
    /// `fallbackTitle` is the exception: it reads a symbolic key, because the
    /// English word "Group" is also the App Intents parameter label, and one
    /// shared key would force a single Polish translation to serve both.
    static let localized = GroupSummaryStrings(
        fallbackTitle: String(localized: .unnamedGroup),
        untitled: String(localized: "Untitled"),
        noExpensesYet: String(localized: "No expenses yet"),
        settleUpHeading: String(localized: "Settle up"),
        expensesHeading: String(localized: "Expenses"),
        everyoneSettled: String(localized: "Everyone is settled up."),
        nothingToSettle: String(localized: "Nothing to settle yet."),
        total: { String(localized: "\($0) total") },
        expenseCount: { String(localized: "\($0) expenses") },
        peopleCount: { String(localized: "\($0) people") },
        transferLine: { from, to, amount in
            String(localized: "• \(from) pays \(to) \(amount)")
        },
        reimbursementLine: { payer, to, amount in
            String(localized: "• \(payer) paid \(to) \(amount)")
        },
        expenseLine: { title, amount, payer in
            String(localized: "• \(title) — \(amount), paid by \(payer)")
        },
        foreignExpenseLine: { title, amount, foreign, payer in
            String(localized: "• \(title) — \(amount) (\(foreign)), paid by \(payer)")
        },
        dated: { line, date in String(localized: "\(line) — \(date)") }
    )
}

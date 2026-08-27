/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

// MARK: - Fixtures

private enum Marked {
    /// Every member replaced by a marker carrying no English, so a line
    /// rendered from a hardcoded literal instead of the pack shows up as prose
    /// in the output rather than merely as a different wording.
    ///
    /// The counts and the amounts still come through, because a pack that
    /// dropped its arguments would pass a test that only looked for the tags.
    static let strings = GroupSummaryStrings(
        fallbackTitle: "«T»",
        untitled: "«U»",
        noExpensesYet: "«N»",
        settleUpHeading: "«S»",
        expensesHeading: "«L»",
        everyoneSettled: "«E»",
        nothingToSettle: "«Z»",
        total: { "«M \($0)»" },
        expenseCount: { "«C \($0)»" },
        peopleCount: { "«P \($0)»" },
        transferLine: { from, to, amount in "«X \(from) \(to) \(amount)»" },
        reimbursementLine: { payer, to, amount in "«R \(payer) \(to) \(amount)»" },
        expenseLine: { title, amount, payer in "«G \(title) \(amount) \(payer)»" },
        foreignExpenseLine: { title, amount, foreign, payer in
            "«F \(title) \(amount) \(foreign) \(payer)»"
        },
        dated: { line, date in "\(line) «D \(date)»" }
    )

    static let locale = Locale(identifier: "en_US")

    static let ann = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, name: "Ann")
    static let ben = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, name: "Ben")

    static func date(_ day: Int, _ month: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    static func summary(
        name: String = "Green Moon Tea",
        spendingCount: Int = 2,
        transfers: [Transfer] = [],
        entries: [GroupSummary.Entry] = []
    ) -> GroupSummary {
        GroupSummary(
            name: name,
            currencyCode: "EUR",
            totalSpent: Money(cents: 12000),
            spendingCount: spendingCount,
            memberCount: 3,
            transfers: transfers,
            entries: entries
        )
    }
}

// MARK: - Tests

@Suite("Group summary wording")
struct GroupSummaryStringsTests {

    @Test("Every word in the message comes from the pack")
    func noEnglishSurvives() {
        let text = Marked.summary(
            transfers: [Transfer(from: Marked.ann, to: Marked.ben, amount: Money(cents: 2000))],
            entries: [
                GroupSummary.Entry(
                    title: "Dinner",
                    amount: Money(cents: 4000),
                    payer: "Ann",
                    date: Marked.date(12, 7)
                ),
                GroupSummary.Entry(
                    title: "",
                    amount: Money(cents: 8000),
                    payer: "Ben",
                    foreign: ForeignAmount(amount: 360, currencyCode: "PLN", rate: 4.5)
                ),
                GroupSummary.Entry(
                    title: "",
                    amount: Money(cents: 2000),
                    payer: "Ann",
                    paidBackTo: "Ben"
                ),
            ]
        ).text(locale: Marked.locale, strings: Marked.strings)

        #expect(text.contains("«M €120.00» · «C 2» · «P 3»"))
        #expect(text.contains("«S»"))
        #expect(text.contains("«X Ann Ben €20.00»"))
        #expect(text.contains("«L»"))
        #expect(text.contains("«G Dinner €40.00 Ann» «D Jul 12»"))
        // Built rather than written out: the currency formatter puts a
        // non-breaking space after `PLN`, which a literal here would get wrong.
        let zloty = ForeignAmount(amount: 360, currencyCode: "PLN", rate: 4.5)!
            .formatted(locale: Marked.locale)
        #expect(text.contains("«F «U» €80.00 \(zloty) Ben»"))
        #expect(text.contains("«R Ann Ben €20.00»"))

        // The wording the pack replaced. Any of it surviving means a literal
        // was left behind in the renderer.
        for leftover in ["total", "pays", "paid by", "Untitled", "Expenses", "Settle up"] {
            #expect(!text.contains(leftover), "\(leftover) came from the renderer, not the pack")
        }
    }

    @Test("The group's own name still wins over the fallback title")
    func nameBeatsFallback() {
        let named = Marked.summary().text(locale: Marked.locale, strings: Marked.strings)
        let unnamed = Marked.summary(name: "").text(locale: Marked.locale, strings: Marked.strings)

        #expect(named.hasPrefix("Green Moon Tea\n"))
        #expect(unnamed.hasPrefix("«T»\n"))
    }

    @Test("An empty group and a settled one still read differently")
    func settledIsNotEmpty() {
        let settled = Marked.summary(spendingCount: 2)
            .text(locale: Marked.locale, strings: Marked.strings)
        let empty = Marked.summary(spendingCount: 0)
            .text(locale: Marked.locale, strings: Marked.strings)

        #expect(settled.contains("«E»"))
        #expect(empty.contains("«Z»"))
        #expect(empty.contains("«N» · «P 3»"))
    }

    @Test("Omitting the pack renders the English the summary shipped with")
    func englishIsTheDefault() {
        let summary = Marked.summary(
            transfers: [Transfer(from: Marked.ann, to: Marked.ben, amount: Money(cents: 2000))]
        )

        #expect(summary.text(locale: Marked.locale)
            == summary.text(locale: Marked.locale, strings: .english))
        #expect(summary.text(locale: Marked.locale).contains("• Ann pays Ben €20.00"))
    }

    @Test("English still agrees with the count it is given")
    func englishPluralsAgree() {
        let one = Marked.summary(spendingCount: 1)
        #expect(GroupSummaryStrings.english.expenseCount(1) == "1 expense")
        #expect(GroupSummaryStrings.english.expenseCount(2) == "2 expenses")
        #expect(GroupSummaryStrings.english.peopleCount(1) == "1 person")
        #expect(GroupSummaryStrings.english.peopleCount(3) == "3 people")
        #expect(one.text(locale: Marked.locale).contains("1 expense ·"))
    }
}

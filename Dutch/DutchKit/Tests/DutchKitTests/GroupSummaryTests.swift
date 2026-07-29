/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import DutchKit

// MARK: - Fixtures

private enum Fixture {
    static let ann = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!, name: "Ann")
    static let ben = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!, name: "Ben")
    static let cara = Participant(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!, name: "Cara")

    /// Pinned so amounts and dates don't change with the machine running the
    /// tests. The group's currency is still EUR — the locale writes the number,
    /// it does not choose the currency.
    static let locale = Locale(identifier: "en_US")

    /// A fixed calendar date, built in UTC so it does not slide across a day
    /// boundary depending on where the test runs.
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
        totalSpent: Money = Money(cents: 12000),
        spendingCount: Int = 2,
        memberCount: Int = 3,
        transfers: [Transfer] = [],
        entries: [GroupSummary.Entry] = []
    ) -> GroupSummary {
        GroupSummary(
            name: name,
            currencyCode: "EUR",
            totalSpent: totalSpent,
            spendingCount: spendingCount,
            memberCount: memberCount,
            transfers: transfers,
            entries: entries
        )
    }
}

// MARK: - Headline

@Suite("Group summary headline")
struct GroupSummaryHeadlineTests {

    @Test("Names the group on the first line")
    func namesGroup() {
        let text = Fixture.summary().text(locale: Fixture.locale)
        #expect(text.hasPrefix("Green Moon Tea\n"))
    }

    @Test("An unnamed group still gets a first line")
    func unnamedGroup() {
        let text = Fixture.summary(name: "").text(locale: Fixture.locale)
        #expect(text.hasPrefix("Group\n"))
    }

    @Test("Totals in the group's currency, counting spending and people")
    func headline() {
        let text = Fixture.summary(totalSpent: Money(cents: 24830), spendingCount: 9, memberCount: 4)
            .text(locale: Fixture.locale)

        #expect(text.contains("€248.30 total · 9 expenses · 4 people"))
    }

    @Test("Singular for one of each")
    func singulars() {
        let text = Fixture.summary(spendingCount: 1, memberCount: 1).text(locale: Fixture.locale)

        #expect(text.contains("1 expense"))
        #expect(text.contains("1 person"))
        #expect(!text.contains("1 expenses"))
        #expect(!text.contains("1 people"))
    }

    /// The currency belongs to the group, not to whoever is reading. A trip
    /// booked in euros stays in euros on a phone set to Polish — otherwise two
    /// members of the same group would paste contradictory numbers into the
    /// same chat.
    @Test("The reader's locale writes the number but never picks the currency")
    func currencyFollowsTheGroup() {
        let summary = Fixture.summary(totalSpent: Money(cents: 24830), spendingCount: 1)

        let polish = summary.text(locale: Locale(identifier: "pl_PL"))
        let american = summary.text(locale: Locale(identifier: "en_US"))

        #expect(polish.contains("248,30"))     // Polish decimal comma
        #expect(american.contains("248.30"))   // American decimal point
        #expect(!polish.contains("zł"))        // but still euros on both
        #expect(american.contains("€"))
    }
}

// MARK: - Settlement

@Suite("Group summary settlement")
struct GroupSummarySettlementTests {

    @Test("Lists who pays whom, in the order the calculator gave them")
    func listsTransfers() {
        let text = Fixture.summary(transfers: [
            Transfer(from: Fixture.ann, to: Fixture.ben, amount: Money(cents: 2450)),
            Transfer(from: Fixture.cara, to: Fixture.ben, amount: Money(cents: 1200)),
        ]).text(locale: Fixture.locale)

        #expect(text.contains("Settle up"))
        #expect(text.contains("• Ann pays Ben €24.50"))
        #expect(text.contains("• Cara pays Ben €12.00"))

        let ann = text.range(of: "Ann pays Ben")!
        let cara = text.range(of: "Cara pays Ben")!
        #expect(ann.lowerBound < cara.lowerBound)
    }

    @Test("Says so when everybody has paid up")
    func settled() {
        let text = Fixture.summary(transfers: []).text(locale: Fixture.locale)

        #expect(text.contains("Everyone is settled up."))
        #expect(!text.contains("Settle up\n"))
    }

    /// A group that has spent nothing is not a group that has settled its
    /// debts, and saying so would read like the app had lost the expenses.
    @Test("An empty group is not congratulated on being settled")
    func emptyGroup() {
        let text = Fixture.summary(totalSpent: .zero, spendingCount: 0, memberCount: 2)
            .text(locale: Fixture.locale)

        #expect(text.contains("No expenses yet · 2 people"))
        #expect(text.contains("Nothing to settle yet."))
        #expect(!text.contains("Everyone is settled up."))
    }

    @Test("The settlement comes before the expense log")
    func settlementLeadsTheLog() {
        let text = Fixture.summary(
            transfers: [Transfer(from: Fixture.ann, to: Fixture.ben, amount: Money(cents: 2450))],
            entries: [.init(title: "Dinner", amount: Money(cents: 9600), payer: "Ben")]
        ).text(locale: Fixture.locale)

        #expect(text.range(of: "Settle up")!.lowerBound < text.range(of: "Expenses")!.lowerBound)
    }
}

// MARK: - Expense log

@Suite("Group summary expense log")
struct GroupSummaryLogTests {

    @Test("Renders an expense as title, amount, payer and date")
    func expenseLine() {
        let text = Fixture.summary(entries: [
            .init(title: "Dinner", amount: Money(cents: 9600), payer: "Ben", date: Fixture.date(12, 7)),
        ]).text(locale: Fixture.locale)

        #expect(text.contains("• Dinner — €96.00, paid by Ben — Jul 12"))
    }

    @Test("An expense with no date drops the date rather than inventing one")
    func undatedExpense() {
        let text = Fixture.summary(entries: [
            .init(title: "Dinner", amount: Money(cents: 9600), payer: "Ben"),
        ]).text(locale: Fixture.locale)

        #expect(text.contains("• Dinner — €96.00, paid by Ben"))
        #expect(!text.contains("paid by Ben —"))
    }

    @Test("An untitled expense still reads as a line")
    func untitledExpense() {
        let text = Fixture.summary(entries: [
            .init(title: "", amount: Money(cents: 500), payer: "Ann"),
        ]).text(locale: Fixture.locale)

        #expect(text.contains("• Untitled — €5.00, paid by Ann"))
    }

    /// The group's own figure leads and the foreign one trails in brackets,
    /// matching the row on screen: `amount` is what every balance is built
    /// from, and the receipt is provenance.
    ///
    /// The `\u{00A0}` is Foundation's, not a typo: currency strings separate
    /// the code from the number with a non-breaking space. Worth keeping rather
    /// than scrubbing — it is what stops a chat app wrapping the line between
    /// `PLN` and the amount.
    @Test("Shows what was handed over abroad next to the converted amount")
    func foreignExpense() {
        let text = Fixture.summary(entries: [
            .init(
                title: "Taxi",
                amount: Money(cents: 1850),
                payer: "Ann",
                date: Fixture.date(11, 7),
                foreign: ForeignAmount(amount: 81.60, currencyCode: "PLN", rate: 4.4111)
            ),
        ]).text(locale: Fixture.locale)

        #expect(text.contains("• Taxi — €18.50 (PLN\u{00A0}81.60), paid by Ann — Jul 11"))
    }

    /// A reimbursement bought nothing, so it is written as a sentence rather
    /// than filed alongside the things the group actually paid for.
    @Test("Renders a settling-up payment as a sentence")
    func paymentLine() {
        let text = Fixture.summary(entries: [
            .init(
                title: "",
                amount: Money(cents: 2000),
                payer: "Ann",
                date: Fixture.date(10, 7),
                paidBackTo: "Ben"
            ),
        ]).text(locale: Fixture.locale)

        #expect(text.contains("• Ann paid Ben €20.00 — Jul 10"))
        #expect(!text.contains("Untitled"))
        #expect(!text.contains("paid by"))
    }

    /// A summary that quietly drops expenses is a record nobody can check,
    /// which is the only reason to paste it into the chat at all.
    @Test("Never truncates the log")
    func keepsEveryEntry() {
        let entries = (1...200).map { index in
            GroupSummary.Entry(title: "Item \(index)", amount: Money(cents: 100), payer: "Ann")
        }

        let text = Fixture.summary(spendingCount: 200, entries: entries).text(locale: Fixture.locale)

        #expect(text.contains("• Item 1 —"))
        #expect(text.contains("• Item 200 —"))
        #expect(text.components(separatedBy: "\n").filter { $0.hasPrefix("• Item ") }.count == 200)
    }

    @Test("Leaves the Expenses heading out when there is nothing to list")
    func noLog() {
        let text = Fixture.summary(entries: []).text(locale: Fixture.locale)
        #expect(!text.contains("Expenses"))
    }
}

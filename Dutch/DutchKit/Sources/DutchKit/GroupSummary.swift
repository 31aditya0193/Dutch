/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// Where a group stands, rendered as plain text for pasting into the chat where
/// the bill was agreed in the first place.
///
/// A snapshot of values, not a view of live records. The text is built from
/// what was true when the summary was made, which is what makes it safe to hand
/// to `ShareLink` and render later, off whatever actor the share sheet feels
/// like calling on.
///
/// Deliberately plain text — no Markdown, no alignment padding. It is read in
/// WhatsApp, Signal and iMessage, none of which agree about formatting and all
/// of which use a proportional font, so a column laid out with spaces arrives
/// ragged. Every line stands on its own instead.
public struct GroupSummary: Sendable, Hashable {

    /// One line of the expense log.
    public struct Entry: Sendable, Hashable {
        /// What it was for. Empty for a settling-up payment, which is described
        /// by who paid whom rather than by a title.
        public let title: String

        /// The amount in the group's currency — the figure the balances are
        /// built from.
        public let amount: Money

        /// Whoever actually paid.
        public let payer: String

        public let date: Date?

        /// What was handed over at the till when that wasn't the group's
        /// currency. Provenance only, exactly as on screen: `amount` was
        /// converted once when the expense was saved and is the only figure
        /// that counts. See `ForeignAmount`.
        public let foreign: ForeignAmount?

        /// Who was paid back, when this entry is a settlement rather than a
        /// purchase. `nil` for an ordinary expense, which is what makes it
        /// usable as the discriminator when rendering the line.
        public let paidBackTo: String?

        public init(
            title: String,
            amount: Money,
            payer: String,
            date: Date? = nil,
            foreign: ForeignAmount? = nil,
            paidBackTo: String? = nil
        ) {
            self.title = title
            self.amount = amount
            self.payer = payer
            self.date = date
            self.foreign = foreign
            self.paidBackTo = paidBackTo
        }
    }

    /// The group's name, as the first line of the message.
    public let name: String

    /// The currency every amount here is expressed in. Held once rather than
    /// per amount: a group settles in exactly one currency, which is the whole
    /// reason the balances can be trusted.
    public let currencyCode: String

    public let totalSpent: Money

    /// How many entries are actual spending rather than settling up, so the
    /// count next to the total adds up to the total.
    public let spendingCount: Int

    public let memberCount: Int

    /// The payments that would settle the group — the part people came for.
    public let transfers: [Transfer]

    /// The full log, newest first, payments included.
    public let entries: [Entry]

    public init(
        name: String,
        currencyCode: String,
        totalSpent: Money,
        spendingCount: Int,
        memberCount: Int,
        transfers: [Transfer],
        entries: [Entry]
    ) {
        self.name = name
        self.currencyCode = currencyCode
        self.totalSpent = totalSpent
        self.spendingCount = spendingCount
        self.memberCount = memberCount
        self.transfers = transfers
        self.entries = entries
    }
}

// MARK: - Rendering

extension GroupSummary {
    /// The shareable message.
    ///
    /// Ordered the way the detail screen is, and for the same reason: what
    /// somebody owes is the answer, and the expense log is the receipt that
    /// backs it up. Anyone who reads only the first few lines has still read
    /// the part that matters.
    ///
    /// The log is never truncated. A long trip makes a long message, but a
    /// summary that quietly drops expenses is a financial record that cannot be
    /// checked — and being checkable is the only reason to paste it into the
    /// group chat rather than just telling everyone the number.
    ///
    /// The dates are the reader's own and the prose is whatever the caller
    /// hands over, which is deliberate rather than half-finished: the expense
    /// rows on screen already write dates in the reader's convention, and a
    /// summary that said `12 lip` on screen and `Jul 12` in the message would
    /// be the odd one out.
    ///
    /// - Parameters:
    ///   - locale: Formats amounts and dates. Injected rather than read from
    ///     `Locale.current` so the output is testable; the currency itself
    ///     always comes from the group, never from the reader.
    ///   - strings: Every word in the message. Defaults to English — see
    ///     `GroupSummaryStrings` for why the wording arrives from outside
    ///     instead of being localized here.
    public func text(
        locale: Locale = .current,
        strings: GroupSummaryStrings = .english
    ) -> String {
        var lines = [
            name.isEmpty ? strings.fallbackTitle : name,
            headline(locale: locale, strings: strings),
            "",
        ]

        lines += settlementLines(locale: locale, strings: strings)

        if !entries.isEmpty {
            lines += [""] + expenseLines(locale: locale, strings: strings)
        }

        return lines.joined(separator: "\n")
    }

    /// The separator is punctuation rather than prose, so it stays here: every
    /// language this has to render puts the same middle dot between the facts.
    private func headline(locale: Locale, strings: GroupSummaryStrings) -> String {
        let people = strings.peopleCount(memberCount)

        guard spendingCount > 0 else {
            return [strings.noExpensesYet, people].joined(separator: " · ")
        }

        return [
            strings.total(totalSpent.formatted(currencyCode: currencyCode, locale: locale)),
            strings.expenseCount(spendingCount),
            people,
        ].joined(separator: " · ")
    }

    private func settlementLines(locale: Locale, strings: GroupSummaryStrings) -> [String] {
        guard !transfers.isEmpty else {
            // Distinguished on purpose: a group that has spent nothing is not
            // the same as one where everybody has paid up, and congratulating
            // an empty group on being settled reads like the app lost the data.
            return [spendingCount > 0 ? strings.everyoneSettled : strings.nothingToSettle]
        }

        return [strings.settleUpHeading] + transfers.map { transfer in
            let amount = transfer.amount.formatted(currencyCode: currencyCode, locale: locale)
            return strings.transferLine(transfer.from.name, transfer.to.name, amount)
        }
    }

    private func expenseLines(locale: Locale, strings: GroupSummaryStrings) -> [String] {
        [strings.expensesHeading] + entries.map {
            $0.line(currencyCode: currencyCode, locale: locale, strings: strings)
        }
    }
}

extension GroupSummary.Entry {
    /// One log line — a purchase, or a payment that settled part of the bill.
    fileprivate func line(
        currencyCode: String,
        locale: Locale,
        strings: GroupSummaryStrings
    ) -> String {
        let money = amount.formatted(currencyCode: currencyCode, locale: locale)

        var line: String
        if let paidBackTo {
            // A sentence, because that is what a reimbursement is: money that
            // moved between two people and bought nothing. Giving it a title
            // and an amount would file it alongside the things the group
            // actually paid for.
            line = strings.reimbursementLine(payer, paidBackTo, money)
        } else {
            // Whole line at a time rather than assembled from a stem and two
            // suffixes: a language that puts the payer before the amount, or
            // the currency note after it, cannot be reached by appending.
            let name = title.isEmpty ? strings.untitled : title
            line = foreign.map {
                strings.foreignExpenseLine(name, money, $0.formatted(locale: locale), payer)
            } ?? strings.expenseLine(name, money, payer)
        }

        if let date {
            line = strings.dated(
                line,
                date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
            )
        }

        return line
    }
}

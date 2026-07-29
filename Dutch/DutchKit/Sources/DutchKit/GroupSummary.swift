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
    /// The prose is English and the dates are not, which is deliberate rather
    /// than half-finished: the app itself is English-only, and its expense rows
    /// already write dates in the reader's own convention. A summary that said
    /// `12 lip` on screen and `Jul 12` in the message would be the odd one out.
    ///
    /// - Parameter locale: Formats amounts and dates. Injected rather than read
    ///   from `Locale.current` so the output is testable; the currency itself
    ///   always comes from the group, never from the reader.
    public func text(locale: Locale = .current) -> String {
        var lines = [name.isEmpty ? "Group" : name, headline(locale: locale), ""]

        lines += settlementLines(locale: locale)

        if !entries.isEmpty {
            lines += [""] + expenseLines(locale: locale)
        }

        return lines.joined(separator: "\n")
    }

    private func headline(locale: Locale) -> String {
        let people = pluralised(memberCount, "person", "people")

        guard spendingCount > 0 else {
            return "No expenses yet · \(people)"
        }

        return [
            "\(totalSpent.formatted(currencyCode: currencyCode, locale: locale)) total",
            pluralised(spendingCount, "expense", "expenses"),
            people,
        ].joined(separator: " · ")
    }

    private func settlementLines(locale: Locale) -> [String] {
        guard !transfers.isEmpty else {
            // Distinguished on purpose: a group that has spent nothing is not
            // the same as one where everybody has paid up, and congratulating
            // an empty group on being settled reads like the app lost the data.
            return [spendingCount > 0 ? "Everyone is settled up." : "Nothing to settle yet."]
        }

        return ["Settle up"] + transfers.map { transfer in
            let amount = transfer.amount.formatted(currencyCode: currencyCode, locale: locale)
            return "• \(transfer.from.name) pays \(transfer.to.name) \(amount)"
        }
    }

    private func expenseLines(locale: Locale) -> [String] {
        ["Expenses"] + entries.map { $0.line(currencyCode: currencyCode, locale: locale) }
    }

    private func pluralised(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

extension GroupSummary.Entry {
    /// One log line — a purchase, or a payment that settled part of the bill.
    fileprivate func line(currencyCode: String, locale: Locale) -> String {
        let money = amount.formatted(currencyCode: currencyCode, locale: locale)

        var line: String
        if let paidBackTo {
            // A sentence, because that is what a reimbursement is: money that
            // moved between two people and bought nothing. Giving it a title
            // and an amount would file it alongside the things the group
            // actually paid for.
            line = "• \(payer) paid \(paidBackTo) \(money)"
        } else {
            line = "• \(title.isEmpty ? "Untitled" : title) — \(money)"
            if let foreign {
                line += " (\(foreign.formatted(locale: locale)))"
            }
            line += ", paid by \(payer)"
        }

        if let date {
            line += " — \(date.formatted(.dateTime.day().month(.abbreviated).locale(locale)))"
        }

        return line
    }
}

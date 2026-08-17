/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import Testing
@testable import Dutch

/// Covers the wording and the batching of new-expense notifications.
///
/// Deliberately not the history walk itself: that needs a real on-disk store
/// with mirroring, a second device to author the transactions, and a silent
/// push to deliver them — none of which a unit test can stand up honestly, and
/// a version faked well enough to pass would be asserting the fake. What is
/// testable is the part that decides what a person actually reads on the lock
/// screen, and that is where the mistakes are: a banner is the one surface in
/// this app somebody sees without being able to tap through to the truth
/// behind it.
@Suite("Expense notifications")
struct ExpenseNotifierTests {

    private static func arrival(
        payer: String = "Alice",
        title: String = "Dinner",
        amount: String = "€45.00",
        isReimbursement: Bool = false,
        groupName: String = "Berlin Trip",
        groupID: UUID = UUID()
    ) -> ExpenseNotifier.Arrival {
        ExpenseNotifier.Arrival(
            groupID: groupID,
            groupName: groupName,
            payer: payer,
            title: title,
            amount: amount,
            isReimbursement: isReimbursement
        )
    }

    // MARK: - Wording

    @Test("An expense names who added it, what it was, and how much")
    func spendingReadsAsASentence() {
        #expect(Self.arrival().body == "Alice added Dinner · €45.00")
    }

    /// A payment is stored as an ordinary expense — see
    /// `GroupStore.recordPayment` — so without the flag the notification would
    /// say "Bob added Settle up", which reads as spending and is the opposite
    /// of what happened to the balance.
    @Test("A payment says it settled up rather than that it was spent")
    func paymentDoesNotReadAsSpending() {
        let arrival = Self.arrival(
            payer: "Bob",
            title: "Settle up",
            amount: "€20.00",
            isReimbursement: true
        )
        #expect(arrival.body == "Bob settled up · €20.00")
    }

    // MARK: - Batching

    @Test("A single arrival is reported in full")
    func oneArrivalIsDetailed() {
        let id = UUID()
        let contents = ExpenseNotifier.contents(for: [Self.arrival(groupID: id)], groupID: id)

        #expect(contents.count == 1)
        #expect(contents[0].title == "Berlin Trip")
        #expect(contents[0].body == "Alice added Dinner · €45.00")
    }

    /// A phone that has been in a pocket all afternoon should show one banner
    /// per trip, not one per receipt. The threshold is a judgement call; that
    /// there *is* one is not.
    @Test("A burst collapses into a single count")
    func burstIsSummarised() {
        let id = UUID()
        let arrivals = (0..<6).map { Self.arrival(title: "Item \($0)", groupID: id) }
        let contents = ExpenseNotifier.contents(for: arrivals, groupID: id)

        #expect(contents.count == 1)
        #expect(contents[0].body == "6 new expenses")
    }

    /// The thread identifier is what keeps a trip's notifications stacked
    /// together in Notification Centre rather than interleaved with every other
    /// app. It also has to be the group, not the expense, or every arrival
    /// starts its own stack.
    @Test("Notifications are threaded by group, and carry it for the tap")
    func threadedAndRoutableByGroup() {
        let id = UUID()
        let contents = ExpenseNotifier.contents(
            for: [Self.arrival(groupID: id), Self.arrival(title: "Taxi", groupID: id)],
            groupID: id
        )

        #expect(contents.count == 2)
        for content in contents {
            #expect(content.threadIdentifier == id.uuidString)
            #expect(content.userInfo["groupID"] as? String == id.uuidString)
        }
    }
}

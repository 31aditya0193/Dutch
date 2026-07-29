/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData

/// Fetch requests for the contents of a single group.
///
/// Reading `group.members` and `group.expenses` off the relationship is the
/// obvious way to do this and the wrong one. `@ObservedObject` on an
/// `ExpenseGroup` publishes when *that object* changes: adding an expense sets
/// `expense.group`, which mutates the group's `expenses` set and does redraw —
/// but correcting an existing expense touches only the `Expense`, and nothing
/// on the group ever changes. The screen went on showing balances computed from
/// the figure that had just been replaced, until leaving the group and coming
/// back rebuilt the view from scratch.
///
/// Fetching the children directly puts them under `@FetchRequest`, which tracks
/// updates to the fetched objects themselves. An edit — typed here or arrived
/// from CloudKit — republishes, the body re-runs, and the settlement is
/// recomputed. This is the same reason the group list uses a fetch request
/// rather than an array: see `GroupStore`.

extension Person {
    /// One group's members, by name — the order every screen shows them in.
    static func request(in group: ExpenseGroup) -> NSFetchRequest<Person> {
        let request = Person.fetchRequest()
        request.predicate = NSPredicate(format: "group == %@", group)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Person.name, ascending: true)]
        return request
    }
}

extension Expense {
    /// One group's expenses, newest first, payments included.
    static func request(in group: ExpenseGroup) -> NSFetchRequest<Expense> {
        let request = Expense.fetchRequest()
        request.predicate = NSPredicate(format: "group == %@", group)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Expense.date, ascending: false),
            // A tiebreak, because a fetched results controller wants a total
            // order: two expenses can share a date to the second when a batch
            // arrives from one sync, and without this their rows swap places on
            // unrelated redraws.
            NSSortDescriptor(keyPath: \Expense.title, ascending: true),
        ]
        // Every row names its payer, and the settlement walks the split. Left to
        // fault on demand that is a main-thread round trip to SQLite per
        // relationship per expense; prefetching folds them into this fetch.
        request.relationshipKeyPathsForPrefetching = ["paidBy", "splitAmong"]
        return request
    }
}

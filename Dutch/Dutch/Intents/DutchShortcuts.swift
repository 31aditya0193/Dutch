/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppIntents

/// The three actions Dutch publishes to Siri, Spotlight, the Shortcuts app and
/// the Action button.
///
/// Three, out of Apple's suggested two to five. Every intent this app defines
/// is available in the Shortcuts app for building custom workflows; what an
/// App Shortcut adds is a spoken phrase and a place in the system's own lists,
/// and that is worth spending only on the things somebody does often enough to
/// say out loud.
///
/// Every phrase has to contain `\(.applicationName)` — the system rejects one
/// that doesn't, and a phrase without the app's name in it would be competing
/// with every other app on the device for the same words.
struct DutchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Assigning this to the Action button is the fastest route into the app
        // there is: press, and the form is open on the trip you're on.
        AppShortcut(
            intent: NewExpenseIntent(),
            phrases: [
                "New expense in \(.applicationName)",
                "Add an expense in \(.applicationName)",
                "Split something in \(.applicationName)",
            ],
            shortTitle: "New Expense",
            systemImageName: "plus.circle"
        )

        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Record an expense in \(.applicationName)",
                "Log a spend in \(.applicationName)",
            ],
            shortTitle: "Add Expense",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: CheckBalanceIntent(),
            phrases: [
                "What do I owe in \(.applicationName)",
                "Check my balance in \(.applicationName)",
                "Am I settled up in \(.applicationName)",
            ],
            shortTitle: "Check Balance",
            systemImageName: "equal.circle"
        )
    }
}

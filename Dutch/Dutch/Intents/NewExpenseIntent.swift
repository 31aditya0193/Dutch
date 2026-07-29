/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppIntents

/// Opens the app on a group's expense form.
///
/// The counterpart to `AddExpenseIntent`, and the one to put on the Action
/// button. Recording by voice is the fastest path when the expense is a number
/// and nothing else; this is for the ordinary case — a foreign receipt, an
/// uneven split, somebody else paying — where the answer is a form, and the
/// friction worth deleting is the four taps it takes to reach one.
///
/// It is also what the Home Screen icon's quick action invokes, so both routes
/// land in exactly the same place.
struct NewExpenseIntent: AppIntent {
    static var title: LocalizedStringResource { "New Expense" }

    static var description: IntentDescription {
        IntentDescription(
            "Opens Dutch on a group's new expense form.",
            categoryName: "Expenses"
        )
    }

    /// Brings the app forward — this intent is a shortcut to a screen, and
    /// there is nothing for it to do in the background. Deprecated in iOS 18 in
    /// favour of `supportedModes`, which needs a deployment target this app
    /// doesn't have.
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Group", description: "Defaults to the group you opened last.")
    var group: GroupEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add an expense to \(\.$group)")
    }

    /// Resolves the group here rather than leaving it to the view, so a
    /// shortcut naming a group that has since been deleted says so instead of
    /// launching the app onto whatever was last on screen.
    ///
    /// Having *no* group is not an error, though — that is a phone the app was
    /// just installed on, and it is exactly when somebody is most likely to
    /// press the Action button to see what happens. The app opens on the group
    /// list, which is where they need to be. Only a named group that has gone
    /// missing is worth interrupting for.
    @MainActor
    func perform() async throws -> some IntentResult {
        let context = PersistenceController.shared.viewContext

        do {
            let group = try resolveGroup(self.group, in: context)
            AppRouter.shared.open(group.id.map { .newExpense(in: $0) })
        } catch DutchIntentError.noGroupChosen {
            // Falls through to a plain launch.
        }

        return .result()
    }
}

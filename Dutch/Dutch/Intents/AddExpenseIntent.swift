/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppIntents
import CoreData
import DutchKit

/// Records an expense without opening the app.
///
/// The point of the whole feature: "add sixty to green-moon-tea" from Siri, the
/// Action button or a Shortcut, with no launch and no screen. Everything it
/// writes goes through `GroupStore.addExpense`, which already took every field
/// this needs — so there is no second way to record an expense, only a second
/// caller.
///
/// **Who paid is the device's identity**, the same `ExpenseDefaults.me` the
/// screens use to say "you owe". That is the honest reading of the sentence —
/// *I* spent sixty — and it is also the only reading available: iOS 17 has no
/// `@IntentParameterDependency`, so a payer parameter could not be narrowed to
/// the members of the chosen group, and the picker would offer everybody from
/// every group. Recording an expense against someone who isn't in the group is
/// a wrong balance, silently; asking the user to say who they are once is not.
///
/// **The amount is in the group's own currency**, and the split is everyone.
/// Both fall out of there being no screen to decide otherwise — the reasoning
/// is with the code, in `IntentWriter`, which is also where the write lives so
/// that it can be tested without the system running this.
struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource { "Add Expense" }

    static var description: IntentDescription {
        IntentDescription(
            "Records an expense you paid for, split evenly between everyone in the group.",
            categoryName: "Expenses"
        )
    }

    /// Runs without bringing the app forward. Deprecated in iOS 18 in favour of
    /// `supportedModes`, which needs a deployment target this app doesn't have.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Amount", description: "In the group's own currency.")
    var amount: Double

    @Parameter(title: "What for", default: "Expense")
    var title: String

    @Parameter(title: "Group", description: "Defaults to the group you opened last.")
    var group: GroupEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) for \(\.$title) to \(\.$group)")
    }

    /// On the main actor, and so is every other intent here.
    ///
    /// Managed objects are not `Sendable` and this target is not on strict
    /// concurrency, so a background context would buy a whole class of problems
    /// to save a write of three records. The app may be launched into the
    /// background to run this; that is fine, the main actor exists either way.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = PersistenceController.shared.viewContext
        let group = try resolveGroup(self.group, in: context)

        let payer = try IntentWriter.addExpense(
            title: title,
            amount: amount,
            to: group,
            in: context
        )

        return .result(
            dialog: confirmation(for: group, amount: Money(amount: amount), payer: payer)
        )
    }

    /// What Siri says back.
    ///
    /// States the figure and the group it landed in, then where that leaves the
    /// user. Repeating the amount is the check on a mishearing — there is no
    /// confirmation step, deliberately, because a confirmation would spend the
    /// five seconds this exists to save, and a wrong entry is one swipe to
    /// delete.
    @MainActor
    private func confirmation(
        for group: ExpenseGroup,
        amount: Money,
        payer: Person
    ) -> IntentDialog {
        let recorded = "Added \(amount.formatted(in: group)) to \(group.name ?? "the group")."

        guard let id = payer.id else { return IntentDialog(stringLiteral: recorded) }

        let settlement = group.settlement()
        let standing = Standing(balance: settlement.balanceByParticipant[id])
        let position = standing.accessibleValue(isMe: true, currencyCode: group.currency)

        // Phrased by `Standing`, the same type the group list and the detail
        // screen use, so Siri and the screens never describe one balance two
        // different ways.
        return IntentDialog(stringLiteral: "\(recorded) \(position).")
    }
}

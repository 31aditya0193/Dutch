import AppIntents
import DutchKit

/// Answers "what do I owe?" without opening the app.
///
/// One question, one sentence, no launch — and the one thing anybody opening a
/// bill-splitting app has come to find out. It reads the same
/// `settlement(members:expenses:)` the group list does and phrases the answer
/// through `Standing`, so Siri and the screens never disagree.
///
/// Needs an identity for the same reason the group row does: without knowing
/// which member is holding the phone there is no "you" to report on. It falls
/// back to the group's total rather than failing, because that is exactly what
/// the list itself does in that case.
struct CheckBalanceIntent: AppIntent {
    static var title: LocalizedStringResource { "Check Balance" }

    static var description: IntentDescription {
        IntentDescription(
            "Says what you owe or are owed in a group.",
            categoryName: "Expenses"
        )
    }

    /// Runs without bringing the app forward. Deprecated in iOS 18 in favour of
    /// `supportedModes`, which needs a deployment target this app doesn't have.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Group", description: "Defaults to the group you opened last.")
    var group: GroupEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Check my balance in \(\.$group)")
    }

    /// Returns the sentence as a value as well as a dialog, so the action is
    /// worth something in a Shortcut that goes on to send it somewhere.
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = PersistenceController.shared.viewContext
        let group = try resolveGroup(self.group, in: context)
        let name = group.name ?? "this group"

        let settlement = group.settlement()
        let members = Array((group.members as? Set<Person>) ?? [])
        let answer: String

        if let me = ExpenseDefaults.me(in: group, among: members), let id = me.id {
            let standing = Standing(balance: settlement.balanceByParticipant[id])
            switch standing {
            case .owes, .isOwed:
                answer = "\(standing.accessibleValue(isMe: true, currencyCode: group.currency)) in \(name)."
            case .settled:
                // Being square yourself doesn't mean the trip is finished, and
                // an answer that stopped at "settled up" would hide that.
                let pending = settlement.transfers.count
                answer = pending == 0
                    ? "You're settled up in \(name), and so is everyone else."
                    : "You're settled up in \(name). \(pending) payment\(pending == 1 ? "" : "s") left between the others."
            }
        } else {
            // No identity set, so there is no "you" — say what the group did,
            // which is the same fallback the group list makes.
            answer = "\(name) has spent \(settlement.totalSpent.formatted(in: group)). Open Dutch and touch and hold your own name to hear your own balance."
        }

        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

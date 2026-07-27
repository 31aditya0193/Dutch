import SwiftUI
import CoreData
import DutchKit

/// Detail screen for a single group: members, expenses, and settlement summary.
///
/// Section order is deliberate — standing, then the payments that fix it, then
/// the log. The settlement is the answer the user came for; the expense list is
/// reference material, and used to sit above it.
struct GroupDetailView: View {
    /// Observed so edits arriving from CloudKit redraw the detail screen.
    @ObservedObject var group: ExpenseGroup

    @Environment(\.managedObjectContext) private var context

    @State private var showingAddExpense = false
    @State private var showingAddMember = false
    @State private var showingShareSheet = false
    @State private var membersPendingDeletion: [Person] = []
    @State private var errorMessage: String?
    /// Bumped on each successful add so the haptic fires once per confirmed
    /// write, rather than on any change to the counts (deletes included).
    @State private var addCount = 0

    private var store: GroupStore { GroupStore(context: context) }

    var body: some View {
        // Gathered once and passed down. Read as computed properties these were
        // re-evaluated at every mention: one full settlement per member row,
        // two more for the Settle Up section, and the member and expense sets
        // sorted four times each.
        let contents = Contents(group: group)

        List {
            summarySection(contents)
            membersSection(contents)
            settleUpSection(contents)
            expensesSection(contents)
        }
        .navigationTitle(group.name ?? "Group")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddExpense = true
                } label: {
                    Label("Add Expense", systemImage: "plus.circle")
                }
                .disabled(contents.members.isEmpty)

                Button {
                    showingShareSheet = true
                } label: {
                    Label("Share Group", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingAddExpense) {
            AddExpenseView(group: group)
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(onAdd: addMember)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareGroupView(group: group)
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: deletionBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: confirmMemberDeletion)
            Button("Cancel", role: .cancel) { membersPendingDeletion = [] }
        } message: {
            Text(deletionMessage)
        }
        .sensoryFeedback(.success, trigger: addCount)
        .errorBanner($errorMessage)
    }

    // MARK: - Sections

    /// Hidden until there is something to total — a large `0.00` on a brand new
    /// group is noise sitting where the useful number will eventually be.
    @ViewBuilder
    private func summarySection(_ contents: Contents) -> some View {
        if !contents.expenses.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total spent")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(contents.totalSpent.formatted(in: group))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("\(count(contents.expenses.count, "expense", "expenses")) · \(count(contents.members.count, "member", "members"))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy, value: contents.totalSpent)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func membersSection(_ contents: Contents) -> some View {
        Section("Members") {
            if contents.members.isEmpty {
                Text("Add members to start splitting expenses.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contents.members, id: \.objectID) { member in
                    MemberBalanceRow(
                        name: member.name ?? "Unnamed",
                        balance: member.id.flatMap { contents.balances[$0] },
                        currencyCode: group.currency
                    )
                }
                .onDelete { offsets in
                    membersPendingDeletion = offsets.map { contents.members[$0] }
                }
            }

            // A full-width row, not a glyph in the section header. This is the
            // only way to make the app usable on first launch, and a header
            // button gave it a ~20pt target well under the 44pt minimum.
            Button {
                showingAddMember = true
            } label: {
                Label("Add Member", systemImage: "person.badge.plus")
            }
        }
    }

    @ViewBuilder
    private func settleUpSection(_ contents: Contents) -> some View {
        if !contents.transfers.isEmpty {
            Section {
                ForEach(contents.transfers) { transfer in
                    TransferRow(transfer: transfer, currencyCode: group.currency)
                }
            } header: {
                Text("Settle Up")
            } footer: {
                // Deliberately not "the fewest payments" — the calculator is
                // greedy, and the true minimum is NP-hard. See
                // `SettlementCalculator.transfers(settling:)`.
                Text("Make these payments and everyone is even.")
            }
        }
    }

    private func expensesSection(_ contents: Contents) -> some View {
        Section("Expenses") {
            if contents.expenses.isEmpty {
                if contents.members.isEmpty {
                    Text("No expenses yet.")
                        .foregroundStyle(.secondary)
                } else {
                    // Members exist, so the app is ready for its main action —
                    // offer it here rather than relying on a toolbar glyph.
                    Button {
                        showingAddExpense = true
                    } label: {
                        Label("Add the First Expense", systemImage: "plus.circle")
                    }
                }
            } else {
                ForEach(contents.expenses, id: \.objectID) { expense in
                    ExpenseRow(expense: expense, currencyCode: group.currency)
                }
                .onDelete { offsets in
                    delete(at: offsets, from: contents.expenses)
                }
            }
        }
    }

    // MARK: - Member deletion

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { !membersPendingDeletion.isEmpty },
            set: { if !$0 { membersPendingDeletion = [] } }
        )
    }

    private var deletionTitle: String {
        guard membersPendingDeletion.count == 1 else {
            return "Remove \(membersPendingDeletion.count) members?"
        }
        return "Remove \(membersPendingDeletion.first?.name ?? "this member")?"
    }

    /// Names the cascade explicitly. Deleting the expenses they paid for is the
    /// correct behaviour — see `GroupStore.delete(_ member:)` — but it is not
    /// something a swipe should do silently.
    private var deletionMessage: String {
        let affected = membersPendingDeletion.reduce(0) { $0 + ($1.paidExpenses?.count ?? 0) }
        guard affected > 0 else {
            return "This won't change anyone else's balance."
        }
        return "This also removes \(count(affected, "expense", "expenses")) they paid for, and recalculates everyone's balance."
    }

    private func confirmMemberDeletion() {
        let doomed = membersPendingDeletion
        membersPendingDeletion = []
        do {
            for member in doomed {
                try store.delete(member)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Actions

    private func addMember(named name: String) {
        do {
            try store.addMember(named: name, to: group)
            addCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet, from expenses: [Expense]) {
        do {
            for index in offsets {
                try store.delete(expenses[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

// MARK: - Render Snapshot

/// Everything `GroupDetailView` reads off its group, gathered in one pass.
///
/// Ordinary computed properties would be re-evaluated at every mention, and
/// this screen mentions them a lot: the member list alone touched the balances
/// once per row, each time walking every expense and re-running the whole
/// settlement to pull out a single number.
private struct Contents {
    let members: [Person]
    let expenses: [Expense]
    let balances: [Participant.ID: Money]
    let transfers: [Transfer]
    let totalSpent: Money

    init(group: ExpenseGroup) {
        members = (group.members as? Set<Person>)?
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
        expenses = (group.expenses as? Set<Expense>)?
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } ?? []

        let settlement = group.settlement()
        balances = settlement.balanceByParticipant
        transfers = settlement.transfers
        totalSpent = settlement.totalSpent
    }
}

// MARK: - Member Row

private struct MemberBalanceRow: View {
    let name: String
    let balance: Money?
    let currencyCode: String

    /// Where a member stands. Modelled as three cases rather than a sign test
    /// so that "even" is its own state — the previous version rendered a zero
    /// balance in green, which reads as being owed money.
    private enum Standing {
        case owes(Money)
        case isOwed(Money)
        case settled

        var tint: Color {
            switch self {
            case .owes: .red
            case .isOwed: .green
            case .settled: .secondary
            }
        }

        /// Redundant to the colour on purpose. Colour alone can't carry the
        /// difference between owing and being owed: it fails for anyone with a
        /// red/green deficiency, and VoiceOver never sees it at all.
        var caption: String {
            switch self {
            case .owes: "owes"
            case .isOwed: "is owed"
            case .settled: "settled up"
            }
        }
    }

    private var standing: Standing {
        guard let balance, !balance.isZero else { return .settled }
        return balance < .zero ? .owes(balance.magnitude) : .isOwed(balance)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 2) {
                switch standing {
                case .owes(let amount), .isOwed(let amount):
                    // Was `.caption`: the smallest text on the row was also the
                    // only number on it.
                    Text(amount.formatted(currencyCode: currencyCode))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(standing.tint)
                        .contentTransition(.numericText())
                case .settled:
                    Text("Settled")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(standing.caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: balance)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue(accessibleValue)
    }

    private var accessibleValue: String {
        switch standing {
        case .owes(let amount):
            "Owes \(amount.formatted(currencyCode: currencyCode))"
        case .isOwed(let amount):
            "Is owed \(amount.formatted(currencyCode: currencyCode))"
        case .settled:
            "Settled up"
        }
    }
}

// MARK: - Transfer Row

private struct TransferRow: View {
    let transfer: Transfer
    let currencyCode: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            // Preferred, while two names and an amount genuinely share a line.
            HStack(spacing: 8) {
                Text(transfer.from.name).fontWeight(.medium)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(transfer.to.name).fontWeight(.medium)
                Spacer(minLength: 12)
                Text(transfer.amount.formatted(currencyCode: currencyCode))
                    .monospacedDigit()
            }

            // Fallback for long names and accessibility text sizes, where the
            // single line used to truncate both names into uselessness.
            VStack(alignment: .leading, spacing: 4) {
                Text("\(transfer.from.name) → \(transfer.to.name)")
                    .fontWeight(.medium)
                Text(transfer.amount.formatted(currencyCode: currencyCode))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(transfer.from.name) pays \(transfer.to.name) \(transfer.amount.formatted(currencyCode: currencyCode))"
        )
    }
}

// MARK: - Expense Row

private struct ExpenseRow: View {
    let expense: Expense
    let currencyCode: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title ?? "Untitled")
                    .font(.body)
                if let date = expense.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let payer = expense.paidBy {
                    // `.secondary`, not `.tertiary`: tertiary is for decoration,
                    // and who paid is the point of the row.
                    Text("Paid by \(payer.name ?? "?")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Text(Money(amount: expense.amount).formatted(currencyCode: currencyCode))
                .font(.callout)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(group: PersistenceController.previewGroup)
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}

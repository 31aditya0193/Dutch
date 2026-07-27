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

    private var members: [Person] {
        (group.members as? Set<Person>)?
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
    }

    private var expenses: [Expense] {
        (group.expenses as? Set<Expense>)?
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } ?? []
    }

    private var balances: [Balance] {
        group.balances
    }

    private var transfers: [Transfer] {
        group.transfers
    }

    var body: some View {
        List {
            summarySection
            membersSection
            settleUpSection
            expensesSection
        }
        .navigationTitle(group.name ?? "Group")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddExpense = true
                } label: {
                    Label("Add Expense", systemImage: "plus.circle")
                }
                .disabled(members.isEmpty)

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
    private var summarySection: some View {
        if !expenses.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total spent")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(group.totalSpent.formatted(in: group))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("\(count(expenses.count, "expense", "expenses")) · \(count(members.count, "member", "members"))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.snappy, value: group.totalSpent)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var membersSection: some View {
        Section("Members") {
            if members.isEmpty {
                Text("Add members to start splitting expenses.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.objectID) { member in
                    MemberBalanceRow(
                        name: member.name ?? "Unnamed",
                        balance: balances.first { $0.participant.id == member.id }?.amount,
                        currencyCode: group.currency
                    )
                }
                .onDelete { offsets in
                    membersPendingDeletion = offsets.map { members[$0] }
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
    private var settleUpSection: some View {
        if !transfers.isEmpty {
            Section {
                ForEach(transfers) { transfer in
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

    private var expensesSection: some View {
        Section("Expenses") {
            if expenses.isEmpty {
                if members.isEmpty {
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
                ForEach(expenses, id: \.objectID) { expense in
                    ExpenseRow(expense: expense, currencyCode: group.currency)
                }
                .onDelete(perform: deleteExpenses)
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

    private func deleteExpenses(at offsets: IndexSet) {
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

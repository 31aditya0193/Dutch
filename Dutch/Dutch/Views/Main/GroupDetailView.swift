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
    @State private var editing: EditTarget?
    @State private var errorMessage: String?
    /// Bumped on each successful add so the haptic fires once per confirmed
    /// write, rather than on any change to the counts (deletes included).
    @State private var addCount = 0
    /// Which member is the person holding this phone, or `nil` if they haven't
    /// said. Mirrored into `@State` rather than read from `ExpenseDefaults` in
    /// the body, because `UserDefaults` is not observable and the badge would
    /// otherwise not move until something else redrew the screen.
    @State private var me: Person?

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
            ExpenseFormView(group: group)
        }
        .sheet(item: $editing) { target in
            ExpenseFormView(editing: target.expense, in: group)
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
        // Resolved against the current roster on every appearance, so an
        // identity whose member was deleted — here or on another device —
        // quietly falls back to third person instead of pointing at nothing.
        .onAppear { me = ExpenseDefaults.me(in: group, among: contents.members) }
    }

    // MARK: - Sections

    /// Hidden until there is something to total — a large `0.00` on a brand new
    /// group is noise sitting where the useful number will eventually be.
    @ViewBuilder
    private func summarySection(_ contents: Contents) -> some View {
        if contents.spendingCount > 0 {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total spent")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(contents.totalSpent.formatted(in: group))
                        .font(.largeTitle.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    // Counts the spending, not the rows: settling up adds an
                    // entry to the list below but buys nothing, and "12
                    // expenses" over a total that added up nine of them is
                    // just wrong.
                    Text("\(count(contents.spendingCount, "expense", "expenses")) · \(count(contents.members.count, "member", "members"))")
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
        Section {
            if contents.members.isEmpty {
                Text("Add members to start splitting expenses.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contents.members, id: \.objectID) { member in
                    MemberBalanceRow(
                        name: member.name ?? "Unnamed",
                        balance: member.id.flatMap { contents.balances[$0] },
                        currencyCode: group.currency,
                        isMe: member == me
                    )
                    // A context menu rather than a row of its own: identity is
                    // set once and never thought about again, and a permanent
                    // "who am I" control would sit in the way of the balances
                    // for the rest of the trip.
                    .contextMenu {
                        if member == me {
                            Button("Not Me", systemImage: "person.slash") {
                                setIdentity(nil)
                            }
                        } else {
                            Button("This Is Me", systemImage: "person.crop.circle.badge.checkmark") {
                                setIdentity(member)
                            }
                        }
                    }
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
        } header: {
            Text("Members")
        } footer: {
            // Shown only until it has been answered — a hint that stays on
            // screen after you've acted on it is just clutter.
            if me == nil, !contents.members.isEmpty {
                Text("Touch and hold your own name to have Dutch address you directly.")
            }
        }
    }

    @ViewBuilder
    private func settleUpSection(_ contents: Contents) -> some View {
        if !contents.transfers.isEmpty {
            Section {
                ForEach(contents.transfers) { transfer in
                    TransferRow(
                        transfer: transfer,
                        currencyCode: group.currency,
                        isMe: transfer.from.id == me?.id,
                        onSettle: { record(transfer, in: contents) }
                    )
                }
            } header: {
                Text("Settle Up")
            } footer: {
                // Deliberately not "the fewest payments" — the calculator is
                // greedy, and the true minimum is NP-hard. See
                // `SettlementCalculator.transfers(settling:)`.
                Text("Make these payments and everyone is even. Mark one paid and it is logged below.")
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
                    // Payments are not editable: there is nothing in one to
                    // correct except whether it happened, and that is what
                    // deleting it says. Ordinary expenses open the form.
                    if expense.isReimbursement {
                        PaymentRow(expense: expense, currencyCode: group.currency)
                    } else {
                        Button {
                            editing = EditTarget(expense: expense)
                        } label: {
                            ExpenseRow(expense: expense, currencyCode: group.currency)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the expense for editing")
                    }
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
    ///
    /// Both halves of the cascade matter. Counting only `paidExpenses` claimed
    /// "this won't change anyone else's balance" for a member who had paid for
    /// nothing but was still splitting other people's expenses — removing them
    /// drops them from `splitAmong`, so those expenses re-divide between fewer
    /// people and every remaining balance moves. The warning said one thing and
    /// the screen behind it did another.
    private var deletionMessage: String {
        let (removed, resplit) = deletionImpact

        switch (removed, resplit) {
        case (0, 0):
            return "This won't change anyone else's balance."
        case (0, _):
            return "\(count(resplit, "expense", "expenses")) they were splitting gets divided between everyone left, so balances change."
        case (_, 0):
            return "This also removes \(count(removed, "expense", "expenses")) they paid for, and recalculates everyone's balance."
        default:
            return "This also removes \(count(removed, "expense", "expenses")) they paid for and re-splits \(count(resplit, "expense", "expenses")) between everyone left. Balances change."
        }
    }

    /// Expenses that disappear with the member, and surviving expenses that get
    /// re-divided without them.
    ///
    /// Both are counted over sets: removing two members at once would otherwise
    /// double-count an expense they were splitting together.
    private var deletionImpact: (removed: Int, resplit: Int) {
        var removed: Set<Expense> = []
        var shared: Set<Expense> = []

        for member in membersPendingDeletion {
            removed.formUnion((member.paidExpenses as? Set<Expense>) ?? [])
            shared.formUnion((member.sharedExpenses as? Set<Expense>) ?? [])
        }

        return (removed.count, shared.subtracting(removed).count)
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

    /// Logs one of the suggested payments as having happened.
    ///
    /// The transfer is expressed in `Participant`s, which the store cannot
    /// write — it needs the `Person` records behind them, hence the lookup.
    /// A transfer naming somebody who is no longer in the group can't be
    /// recorded, and silently doing nothing would look like the tap missed.
    private func record(_ transfer: Transfer, in contents: Contents) {
        guard
            let payer = contents.person[transfer.from.id],
            let recipient = contents.person[transfer.to.id]
        else {
            errorMessage = "That member is no longer in this group."
            return
        }

        do {
            try store.recordPayment(
                from: payer,
                to: recipient,
                amount: transfer.amount,
                in: group
            )
            addCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setIdentity(_ member: Person?) {
        ExpenseDefaults.rememberMe(member, in: group)
        withAnimation(.snappy) { me = member }
    }

    private func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

// MARK: - Edit Target

/// Wraps the expense being edited so it can drive `sheet(item:)`.
///
/// `Expense` cannot be `Identifiable` off its own `id`: every attribute is
/// optional for CloudKit's sake, and a sheet keyed on a `nil` id would never
/// present. The object id is always there, and is exactly as stable as the
/// object itself.
private struct EditTarget: Identifiable {
    let expense: Expense
    var id: NSManagedObjectID { expense.objectID }
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
    /// How many of `expenses` are actual spending rather than settling up.
    let spendingCount: Int

    /// Members keyed by id, so recording a payment can get from the `Transfer`
    /// the settlement produced back to the `Person` the store needs to write.
    let person: [UUID: Person]

    init(group: ExpenseGroup) {
        let roster = (group.members as? Set<Person>)?
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
        members = roster
        expenses = (group.expenses as? Set<Expense>)?
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) } ?? []

        person = Dictionary(
            roster.compactMap { member in member.id.map { ($0, member) } },
            uniquingKeysWith: { first, _ in first }
        )

        let settlement = group.settlement()
        balances = settlement.balanceByParticipant
        transfers = settlement.transfers
        totalSpent = settlement.totalSpent
        spendingCount = settlement.spendingCount
    }
}

// MARK: - Member Row

private struct MemberBalanceRow: View {
    let name: String
    let balance: Money?
    let currencyCode: String
    /// Whether this is the person holding the phone, which changes the caption
    /// from a statement about someone else into one about them.
    let isMe: Bool

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
        func caption(isMe: Bool) -> String {
            switch self {
            case .owes: isMe ? "you owe" : "owes"
            case .isOwed: isMe ? "you are owed" : "is owed"
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

            // A badge rather than replacing the name with "You": the name is
            // still how everyone else in the group refers to this person, and
            // dropping it makes the row harder to scan, not easier.
            if isMe {
                Text("You")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)  // carried by the label below
            }

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

                Text(standing.caption(isMe: isMe))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .animation(.snappy, value: balance)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isMe ? "\(name), you" : name)
        .accessibilityValue(accessibleValue)
    }

    private var accessibleValue: String {
        switch standing {
        case .owes(let amount):
            "\(isMe ? "You owe" : "Owes") \(amount.formatted(currencyCode: currencyCode))"
        case .isOwed(let amount):
            "\(isMe ? "You are owed" : "Is owed") \(amount.formatted(currencyCode: currencyCode))"
        case .settled:
            "Settled up"
        }
    }
}

// MARK: - Transfer Row

private struct TransferRow: View {
    let transfer: Transfer
    let currencyCode: String
    /// Whether the payment is one *this* device's owner has to make.
    let isMe: Bool
    let onSettle: () -> Void

    private var payer: String { isMe ? "You" : transfer.from.name }

    private var amount: String {
        transfer.amount.formatted(currencyCode: currencyCode)
    }

    var body: some View {
        HStack(spacing: 12) {
            ViewThatFits(in: .horizontal) {
                // Preferred, while two names and an amount genuinely share a line.
                HStack(spacing: 8) {
                    Text(payer).fontWeight(.medium)
                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(transfer.to.name).fontWeight(.medium)
                    Spacer(minLength: 12)
                    Text(amount).monospacedDigit()
                }

                // Fallback for long names and accessibility text sizes, where the
                // single line used to truncate both names into uselessness.
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(payer) → \(transfer.to.name)")
                        .fontWeight(.medium)
                    Text(amount)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                isMe
                    ? "You pay \(transfer.to.name) \(amount)"
                    : "\(transfer.from.name) pays \(transfer.to.name) \(amount)"
            )

            // A visible button, not a swipe action. Settling up is the second
            // thing anyone comes to this screen to do, and hiding it behind a
            // gesture with no affordance means most people never find it.
            // `.borderless` keeps it a hit target of its own inside the row.
            Button("Mark Paid", action: onSettle)
                .font(.caption.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    isMe
                        ? "Mark your \(amount) payment to \(transfer.to.name) as paid"
                        : "Mark \(transfer.from.name)'s \(amount) payment to \(transfer.to.name) as paid"
                )
        }
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

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money(amount: expense.amount).formatted(currencyCode: currencyCode))
                    .font(.callout)
                    .monospacedDigit()

                // What was actually handed over, for expenses paid abroad. The
                // group's own figure stays the prominent one — it is the number
                // the balances are built from — with this as its receipt.
                if let foreign = expense.foreignAmount {
                    Text(foreign.formatted())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Payment Row

/// A settling-up payment in the expense list.
///
/// Rendered as a sentence rather than a title and an amount, because that is
/// what it is: money that moved between two people and bought nothing. It sits
/// in the same list as the expenses so it can be deleted the same way — which
/// is the only undo a mis-tapped "Mark Paid" needs.
private struct PaymentRow: View {
    let expense: Expense
    let currencyCode: String

    private var sentence: String {
        let payer = expense.paidBy?.name ?? "?"
        let recipient = expense.reimbursementRecipient?.name ?? "?"
        return "\(payer) paid \(recipient)"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(sentence)
                    .font(.callout)
                if let date = expense.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            // Secondary, unlike an expense amount: this figure is not part of
            // what the trip cost, and giving it the same weight as a real
            // expense would suggest it was.
            Text(Money(amount: expense.amount).formatted(currencyCode: currencyCode))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(sentence) \(Money(amount: expense.amount).formatted(currencyCode: currencyCode))"
        )
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(group: PersistenceController.previewGroup)
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}

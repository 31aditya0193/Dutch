/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import SwiftUI
import CoreData
import CoreTransferable
import DutchKit

/// Detail screen for a single group: members, expenses, and settlement summary.
///
/// Section order is deliberate — standing, then the payments that fix it, then
/// the log. The settlement is the answer the user came for; the expense list is
/// reference material, and used to sit above it.
struct GroupDetailView: View {
    /// Observed for the group's own fields — its name and currency.
    @ObservedObject var group: ExpenseGroup

    /// The contents come from fetch requests rather than from `group.members`
    /// and `group.expenses`, so that *editing* an expense recomputes the
    /// balances. Observing the group alone only catches changes to the group
    /// itself, and correcting an amount never touches it. See
    /// `Expense.request(in:)`.
    @FetchRequest private var members: FetchedResults<Person>
    @FetchRequest private var expenses: FetchedResults<Expense>

    init(group: ExpenseGroup) {
        self.group = group
        _members = FetchRequest(fetchRequest: Person.request(in: group), animation: .snappy)
        _expenses = FetchRequest(fetchRequest: Expense.request(in: group), animation: .snappy)
    }

    @Environment(\.managedObjectContext) private var context

    @State private var showingAddExpense = false
    @State private var showingAddMember = false
    @State private var showingShareSheet = false
    @State private var showingEditGroup = false
    @State private var membersPendingDeletion: [Person] = []
    @State private var formTarget: FormTarget?
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

    /// Consulted for a pending `.newExpense`, which `GroupListView` pushes this
    /// screen for but cannot act on — the form is a sheet belonging here.
    private var router: AppRouter { AppRouter.shared }

    var body: some View {
        // Gathered once and passed down. Read as computed properties these were
        // re-evaluated at every mention: one full settlement per member row,
        // two more for the Settle Up section, and the member and expense sets
        // sorted four times each.
        let contents = Contents(
            group: group,
            members: Array(members),
            expenses: Array(expenses)
        )

        List {
            summarySection(contents)
            membersSection(contents)
            settleUpSection(contents)
            expensesSection(contents)
        }
        // Here as well as on the group list, because this is the screen someone
        // stares at waiting for an expense their friend just added. No status
        // line to go with it: the list is where "is everything here?" is asked,
        // and this screen is already dense. See `CloudSyncMonitor` for what the
        // pull actually does.
        .refreshable { await CloudSyncMonitor.shared.refresh() }
        .navigationTitle(group.name ?? "Group")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Leftmost of the three: renaming and restyling is something
                // you do once, and it has no business sitting where the thumb
                // lands for "add an expense".
                //
                // In the toolbar rather than on the summary block, because that
                // block only exists once there is spending — and a brand new
                // group with a name typed in a hurry is exactly the one you
                // want to fix.
                Button {
                    showingEditGroup = true
                } label: {
                    Label("Edit Group", systemImage: "pencil")
                }

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
        .sheet(item: $formTarget) { target in
            switch target.mode {
            case .edit:
                ExpenseFormView(editing: target.expense, in: group)
            case .duplicate:
                ExpenseFormView(duplicating: target.expense, in: group)
            }
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(onAdd: addMember)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareGroupView(group: group)
        }
        .sheet(isPresented: $showingEditGroup) {
            EditGroupSheet(group: group, onSave: updateGroup)
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
        .onAppear {
            // Compared before assigning, because `@State` invalidates on any
            // write and not only on a change of value — and this runs on every
            // return from the expense form, where the answer is the same one it
            // was when the sheet went up.
            let resolved = ExpenseDefaults.me(in: group, among: contents.members)
            if resolved != me { me = resolved }
            // What makes "add an expense" mean something without a group being
            // named — from the Action button, the Home Screen icon, or Siri.
            // Recorded on arrival rather than on any edit, because the question
            // it answers is "which trip am I on", and opening a group is the
            // whole of the evidence for that.
            ExpenseDefaults.rememberOpened(group)
            openPendingExpense()
        }
        .onChange(of: router.destination) { openPendingExpense() }
    }

    /// Opens the form if an intent asked for a new expense *in this group*.
    ///
    /// Checked against the group rather than taken on trust: the destination is
    /// global, and this screen can be on top of a different group entirely when
    /// one arrives. Consumed either way once acted on, so returning here later
    /// doesn't reopen the sheet.
    private func openPendingExpense() {
        guard case .newExpense(let id) = router.destination, id == group.id else { return }
        router.destination = nil
        // Nothing to enter until somebody can be charged for it, and the form
        // would open with an empty roster and a disabled Save.
        guard !members.isEmpty else {
            errorMessage = "Add a member to this group first."
            return
        }
        showingAddExpense = true
    }

    // MARK: - Sections

    /// The group's identity, and its total once there is one.
    ///
    /// The section itself is unconditional — it is the only thing on this screen
    /// that says *which* group you are looking at, and a group that hasn't been
    /// spent in yet is precisely the one you might have opened by mistake. What
    /// is conditional is the number: a large `0.00` on a brand new group is
    /// noise sitting where the useful figure will eventually be, so until then
    /// the block is the tile and a quiet line about where the group stands.
    private func summarySection(_ contents: Contents) -> some View {
        Section {
            // The same tile as the list row, so arriving here confirms you
            // opened the group you meant to. Larger, because this is the one
            // place it isn't competing with a column of others.
            HStack(alignment: .top, spacing: 16) {
                GroupIcon(group.appearance, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    if contents.spendingCount > 0 {
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
                    } else {
                        Text("Nothing spent yet")
                            .font(.headline)

                        // Only once there is a roster. "0 members" next to
                        // "nothing spent yet" is the same fact told twice, and
                        // the members section below already asks for the first
                        // one in words.
                        if !contents.members.isEmpty {
                            Text(count(contents.members.count, "member", "members"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.snappy, value: contents.totalSpent)
            .accessibilityElement(children: .combine)

            // Withheld until there is something to summarise: the shared text
            // is the total and the payments settling it, and neither exists yet.
            //
            // Here rather than in the toolbar, for two reasons. The toolbar
            // already owns a share glyph — that one invites people into the
            // group, and hanging a second, different share off the same
            // symbol makes both a coin flip. And this section is exactly
            // the thing being shared: the total, and what it resolves to.
            if contents.spendingCount > 0 {
                ShareLink(
                    item: SharedSummary(summary: contents.summary),
                    preview: SharePreview(group.name ?? "Group")
                ) {
                    Label("Share Summary", systemImage: "doc.plaintext")
                }
                .accessibilityHint("Copies who owes whom, the total and the expense list as text")
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
                        avatar: contents.avatars[member],
                        isLinked: CloudIdentity.isSomeoneElse(member),
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
                        } else if CloudIdentity.isSomeoneElse(member) {
                            // Offered as a disabled row rather than hidden, so
                            // the answer to "why can't I pick this one?" is on
                            // screen instead of being an unexplained gap in a
                            // menu every other row has.
                            Button("Already Someone Else", systemImage: "person.fill.xmark") {}
                                .disabled(true)
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
                            formTarget = FormTarget(expense: expense, mode: .edit)
                        } label: {
                            ExpenseRow(expense: expense, currencyCode: group.currency)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the expense for editing")
                        // Long-press rather than a swipe action or a button on
                        // the row: repeating an expense is common enough to
                        // want and rare enough that it shouldn't take up space
                        // in a list people mostly read. Payments are left out —
                        // a settlement is recorded from the section above, and
                        // paying the same debt twice is a mistake, not a
                        // shortcut.
                        .contextMenu {
                            Button("Duplicate", systemImage: "plus.square.on.square") {
                                formTarget = FormTarget(expense: expense, mode: .duplicate)
                            }
                        }
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

    private func updateGroup(name: String, appearance: GroupAppearance) {
        do {
            try store.update(group, name: name, appearance: appearance)
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

    /// Records who this device belongs to, both ways at once.
    ///
    /// The local key first, because it is the one that cannot fail: it needs no
    /// iCloud account and no network, and it is all a group that was never
    /// shared will ever have. The claim then rides on top when there *is* an
    /// account, which is what carries the answer to this person's other devices
    /// and to everyone else's copy of the group.
    ///
    /// A failed claim is deliberately quiet. Identity is a label — the balances
    /// do not depend on it — and an error banner over "you tapped your own name"
    /// would be a louder failure than the thing that failed.
    private func setIdentity(_ member: Person?) {
        ExpenseDefaults.rememberMe(member, in: group)
        try? store.claim(member, in: group)
        withAnimation(.snappy) { me = member }
    }

    private func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        "\(value) \(value == 1 ? singular : plural)"
    }
}

// MARK: - Form Target

/// Wraps the expense the form is opening on, and what it is opening for, so it
/// can drive `sheet(item:)`.
///
/// `Expense` cannot be `Identifiable` off its own `id`: every attribute is
/// optional for CloudKit's sake, and a sheet keyed on a `nil` id would never
/// present. The object id is always there, and is exactly as stable as the
/// object itself — and the mode joins it so that duplicating the row you just
/// finished editing counts as a different sheet rather than the same one again.
private struct FormTarget: Identifiable {
    enum Mode: String {
        /// Rewrites the expense in place.
        case edit
        /// Leaves it alone and adds a copy.
        case duplicate
    }

    let expense: Expense
    let mode: Mode

    var id: String { "\(mode.rawValue)-\(expense.objectID.uriRepresentation())" }
}

// MARK: - Render Snapshot

/// Everything `GroupDetailView` reads off its group, gathered in one pass.
///
/// Ordinary computed properties would be re-evaluated at every mention, and
/// this screen mentions them a lot: the member list alone touched the balances
/// once per row, each time walking every expense and re-running the whole
/// settlement to pull out a single number.
@MainActor
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

    /// One colour per member, resolved over the whole roster at once — see
    /// `RosterAvatars` for why it cannot be done a row at a time.
    let avatars: RosterAvatars

    /// The same numbers as a snapshot free of managed objects, ready to be
    /// rendered as shareable text. Built here because everything it needs is
    /// already in hand — it costs one more pass over `expenses`, not another
    /// settlement.
    let summary: GroupSummary

    /// Takes the roster and the log already sorted, because they arrive from
    /// fetch requests that sorted them in SQLite — see `Person.request(in:)`.
    init(group: ExpenseGroup, members roster: [Person], expenses log: [Expense]) {
        members = roster
        expenses = log

        person = Dictionary(
            roster.compactMap { member in member.id.map { ($0, member) } },
            uniquingKeysWith: { first, _ in first }
        )

        avatars = RosterAvatars(roster)

        let settlement = group.settlement(members: roster, expenses: log)
        balances = settlement.balanceByParticipant
        transfers = settlement.transfers
        totalSpent = settlement.totalSpent
        spendingCount = settlement.spendingCount

        summary = group.summary(from: settlement, expenses: log, memberCount: roster.count)
    }
}

// MARK: - Shared Summary

/// The group summary as something `ShareLink` can hand to the share sheet.
///
/// A `Transferable` wrapper rather than the finished `String`, because
/// `ShareLink` takes its item eagerly: passing the text itself would build the
/// whole message — a line per expense, formatted — on every redraw of this
/// screen, for a button most people tap once a trip. `ProxyRepresentation`
/// defers that to the tap.
///
/// Deferring is only safe because `GroupSummary` is a value snapshot with no
/// managed objects in it, so the closure can run whenever and on whatever actor
/// the share sheet chooses. Capturing anything Core Data owns here would be a
/// crash waiting for a slow share sheet.
private struct SharedSummary: Transferable {
    let summary: GroupSummary

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { $0.summary.text() }
    }
}

// MARK: - Member Row

private struct MemberBalanceRow: View {
    let name: String
    let avatar: PersonAvatar
    /// Whether this member has been claimed by an iCloud account other than
    /// this device's — which is to say, they are here on a phone of their own
    /// rather than being a name somebody typed in on everyone's behalf.
    let isLinked: Bool
    let balance: Money?
    let currencyCode: String
    /// Whether this is the person holding the phone, which changes the caption
    /// from a statement about someone else into one about them.
    let isMe: Bool

    private var standing: Standing { Standing(balance: balance) }

    private var accessibleName: String {
        if isMe { return "\(name), you" }
        return isLinked ? "\(name), joined on iCloud" : name
    }

    var body: some View {
        // Two nested stacks rather than one: the avatar is a circle with no
        // baseline to align to, and putting it in the `.firstTextBaseline` stack
        // pinned its bottom edge to the name and left it floating high.
        HStack(spacing: 12) {
            PersonIcon(avatar)

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
                        .background(.tint.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)  // carried by the label below
                } else if isLinked {
                    // A glyph rather than a second capsule. "You" is worth a
                    // badge because it changes how the whole row reads; this
                    // only says the row has a person behind it, and a row of
                    // capsules would make the one that matters stop standing
                    // out.
                    Image(systemName: "checkmark.icloud")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)  // carried by the label below
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 2) {
                    switch standing {
                    case .owes(let amount), .isOwed(let amount):
                        // Was `.caption`: the smallest text on the row was also
                        // the only number on it.
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
        }
        .animation(.snappy, value: balance)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibleName)
        .accessibilityValue(standing.accessibleValue(isMe: isMe, currencyCode: currencyCode))
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

import CoreData
import DutchKit
import SwiftUI

/// Main screen showing all expense groups — both the user's own and any that
/// have been shared with them.
struct GroupListView: View {
    @Environment(\.managedObjectContext) private var context

    /// Reads go through `@FetchRequest` so changes synced down from CloudKit
    /// refresh the list on their own, with no manual reload.
    ///
    /// The spring is deliberate: `.default` is an ease, which reads as
    /// mechanical when a row arrives from a sync the user didn't initiate.
    @FetchRequest(
        fetchRequest: GroupListView.groupsRequest,
        animation: .spring(response: 0.35, dampingFraction: 0.8)
    )
    private var groups: FetchedResults<ExpenseGroup>

    /// Only the groups. Each row fetches its own contents — and prefetches the
    /// relationships the settlement walks — because a row that read them off
    /// the relationship sets could not see an expense being edited. See
    /// `Expense.request(in:)`.
    private static var groupsRequest: NSFetchRequest<ExpenseGroup> {
        let request = ExpenseGroup.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ExpenseGroup.creationDate, ascending: false)
        ]
        return request
    }

    /// Path-based navigation so creating a group can push straight into it.
    @State private var path: [ExpenseGroup] = []
    @State private var showingNewGroup = false
    @State private var showingJoinGroup = false
    @State private var errorMessage: String?
    /// Held until the sheet has finished dismissing — pushing onto the path
    /// while a sheet is still on screen is a reliable way to have the push
    /// silently swallowed.
    @State private var groupToOpen: ExpenseGroup?

    private var store: GroupStore { GroupStore(context: context) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(groups) { group in
                    NavigationLink(value: group) {
                        GroupRow(group: group)
                    }
                }
                .onDelete(perform: delete)
            }
            .navigationDestination(for: ExpenseGroup.self) { group in
                GroupDetailView(group: group)
            }
            // Outside the List, so the empty state centres on the screen
            // instead of inside a single inset row with a separator under it.
            .overlay {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups", systemImage: "rectangle.3.group")
                    } description: {
                        Text("Create a group to start splitting expenses, or join one with a QR code.")
                    } actions: {
                        // An empty state without a next action is a dead end.
                        Button("Create a Group") { showingNewGroup = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Dutch")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingJoinGroup = true
                    } label: {
                        Label("Join a Group", systemImage: "qrcode.viewfinder")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewGroup = true
                    } label: {
                        Label("New Group", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewGroup, onDismiss: openPendingGroup) {
                NewGroupSheet(onCreate: createGroup)
            }
            .sheet(isPresented: $showingJoinGroup) {
                JoinGroupView()
            }
            .errorBanner($errorMessage)
        }
    }

    // MARK: - Actions

    private func createGroup(
        named name: String,
        currencyCode: String,
        appearance: GroupAppearance
    ) {
        do {
            groupToOpen = try store.createGroup(
                named: name,
                currencyCode: currencyCode,
                appearance: appearance
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A new group is empty and useless until it has members, so drop the user
    /// into it rather than leaving them on a list to tap the row they just made.
    private func openPendingGroup() {
        guard let group = groupToOpen else { return }
        groupToOpen = nil
        path = [group]
    }

    private func delete(at offsets: IndexSet) {
        do {
            for index in offsets {
                try store.delete(groups[index])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct GroupRow: View {
    /// Observed for the group's own fields — name and share URL.
    @ObservedObject var group: ExpenseGroup

    /// The row's numbers come from fetch requests for the same reason the
    /// detail screen's do: an expense edited anywhere changes the `Expense`
    /// and nothing on the group, so a row reading the relationship set keeps
    /// showing the total it had when it was last built. See
    /// `Expense.request(in:)`.
    @FetchRequest private var members: FetchedResults<Person>
    @FetchRequest private var expenses: FetchedResults<Expense>

    /// Which member is the person holding this phone, or `nil` if they haven't
    /// said — in which case the row falls back to reporting the group as a
    /// whole, which is all it could say before identity existed.
    @State private var me: Person?

    init(group: ExpenseGroup) {
        self.group = group
        _members = FetchRequest(fetchRequest: Person.request(in: group))
        _expenses = FetchRequest(fetchRequest: Expense.request(in: group))
    }

    var body: some View {
        // One settlement per row. `totalSpent` and `transfers` were separate
        // walks of the same expenses, and `transfers` rebuilt the balances on
        // top of that — three passes to render two numbers.
        let settlement = group.settlement(members: Array(members), expenses: Array(expenses))
        let memberCount = members.count
        let expenseCount = expenses.count
        let standing = me?.id.map { Standing(balance: settlement.balanceByParticipant[$0]) }

        // The tile sits outside the fitting, so it is present in both branches
        // and the fit is decided on the width the text actually gets.
        HStack(spacing: 12) {
            GroupIcon(group.appearance)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    identity(memberCount: memberCount, expenseCount: expenseCount)
                    Spacer(minLength: 12)
                    money(settlement, standing: standing, alignment: .trailing)
                }

                // Once names, currency and type size stop sharing a line, stack
                // rather than truncate.
                VStack(alignment: .leading, spacing: 8) {
                    identity(memberCount: memberCount, expenseCount: expenseCount)
                    money(settlement, standing: standing, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(
            standing?.accessibleValue(isMe: true, currencyCode: group.currency)
                ?? groupAccessibleValue(settlement)
        )
        .onAppear { resolveIdentity() }
        // Identity is set on the detail screen, which sits directly on top of
        // this list. `UserDefaults` is not observable and popping back doesn't
        // re-run `onAppear` on a row that never left the screen, so without
        // this the row would keep showing the group total until something else
        // redrew it.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            resolveIdentity()
        }
        .onChange(of: members.count) { resolveIdentity() }
    }

    /// Re-resolves against the current roster on every appearance, so an
    /// identity whose member was deleted — here or on another device — quietly
    /// falls back to the group-wide numbers instead of pointing at nothing.
    private func resolveIdentity() {
        let resolved = ExpenseDefaults.me(in: group, among: Array(members))
        guard resolved != me else { return }
        withAnimation(.snappy) { me = resolved }
    }

    @ViewBuilder
    private func identity(memberCount: Int, expenseCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(group.name ?? "Unnamed")
                    .font(.headline)

                if group.cloudKitShareURL != nil {
                    Image(systemName: "person.2.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Shared group")
                }
            }

            // No word sequence here, deliberately: it is a label for pairing a
            // new phone with a group and belongs next to the QR code on the
            // share screen, not on the list somebody reads every day.

            // Both glyphs filled, both labelled: the old row mixed
            // `person.2.fill` with an outline `person` in the same group, and
            // read to VoiceOver as two bare numbers.
            HStack(spacing: 12) {
                Label("\(memberCount)", systemImage: "person.2.fill")
                    .accessibilityLabel("\(memberCount) members")
                Label("\(expenseCount)", systemImage: "list.bullet.rectangle.fill")
                    .accessibilityLabel("\(expenseCount) expenses")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .symbolRenderingMode(.hierarchical)
        }
    }

    /// The one number worth reading from the list.
    ///
    /// Once the device knows which member is holding it, that number is what
    /// *they* owe or are owed — the question anyone opening a bill-splitting
    /// app came to ask, and previously one tap away on every group. The group's
    /// total spent gives up its place here rather than sharing the column with
    /// it: two figures in the same corner make each of them a thing to decode,
    /// and the total is the hero of the detail screen, which is a tap away.
    ///
    /// Without an identity there is no personal figure to show, so the row says
    /// exactly what it always did.
    @ViewBuilder
    private func money(
        _ settlement: ExpenseGroup.Settlement,
        standing: Standing?,
        alignment: HorizontalAlignment
    ) -> some View {
        let pending = settlement.transfers.count

        VStack(alignment: alignment, spacing: 2) {
            switch standing {
            case .owes(let amount), .isOwed(let amount):
                Text(amount.formatted(in: group))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(standing?.tint ?? .primary)
                    // The figure changes whenever anyone adds an expense,
                    // including from another device — roll the digits so it's
                    // visible.
                    .contentTransition(.numericText())

                Text(standing?.caption(isMe: true) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case .settled:
                Text("Settled up")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                // Being square with everyone doesn't mean the group is done,
                // and a row that stopped at "Settled up" hid that.
                Text(pending == 0 ? "everyone's even" : "\(pending) to settle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

            case nil:
                Text(settlement.totalSpent.formatted(in: group))
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(pending == 0 ? "Settled up" : "\(pending) to settle")
                    .font(.caption2)
                    .foregroundStyle(pending == 0 ? .secondary : .primary)
            }
        }
        .animation(.snappy, value: standing)
        .animation(.snappy, value: settlement.totalSpent)
    }

    /// What the row says to VoiceOver when it has no personal figure to report.
    private func groupAccessibleValue(_ settlement: ExpenseGroup.Settlement) -> String {
        let total = settlement.totalSpent.formatted(in: group)
        let pending = settlement.transfers.count
        return pending == 0
            ? "\(total) total, settled up"
            : "\(total) total, \(pending) payments to settle"
    }
}

#Preview {
    GroupListView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}

import SwiftUI
import CoreData
import DutchKit

/// Detail screen for a single group: members, expenses, and settlement summary.
struct GroupDetailView: View {
    /// Observed so edits arriving from CloudKit redraw the detail screen.
    @ObservedObject var group: ExpenseGroup

    @Environment(\.managedObjectContext) private var context

    @State private var showingAddExpense = false
    @State private var showingAddMember = false
    @State private var newMemberName = ""
    @State private var showingShareSheet = false
    @State private var errorMessage: String?

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
            // ── Members ─────────────────────────────────────────
            Section {
                if members.isEmpty {
                    Text("Add members to start splitting expenses.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(members, id: \.objectID) { member in
                        MemberBalanceRow(
                            name: member.name ?? "Unnamed",
                            balance: balances.first { $0.participant.id == member.id }?.amount
                        )
                    }
                }
            } header: {
                HStack {
                    Text("Members")
                    Spacer()
                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "person.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Add Member")
                }
            }

            // ── Expenses ────────────────────────────────────────
            Section("Expenses") {
                if expenses.isEmpty {
                    Text("No expenses yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expenses, id: \.objectID) { expense in
                        ExpenseRow(expense: expense)
                    }
                }
            }

            // ── Settlements ─────────────────────────────────────
            if !transfers.isEmpty {
                Section("Settle Up") {
                    ForEach(transfers) { transfer in
                        HStack {
                            Text(transfer.from.name)
                                .fontWeight(.medium)
                            Text("pays")
                                .foregroundStyle(.secondary)
                            Text(transfer.to.name)
                                .fontWeight(.medium)
                            Spacer()
                            Text(transfer.amount.formatted())
                                .monospacedDigit()
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .navigationTitle(group.name ?? "Group")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddExpense = true
                } label: {
                    Label("Add Expense", systemImage: "plus.circle")
                }

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
        .alert("Add Member", isPresented: $showingAddMember) {
            TextField("Name", text: $newMemberName)
            Button("Cancel", role: .cancel) { newMemberName = "" }
            Button("Add", action: addMember)
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareGroupView(group: group)
        }
        .alert("Something Went Wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func addMember() {
        let trimmed = newMemberName.trimmingCharacters(in: .whitespacesAndNewlines)
        newMemberName = ""
        guard !trimmed.isEmpty else { return }

        do {
            try store.addMember(named: trimmed, to: group)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Member Row

private struct MemberBalanceRow: View {
    let name: String
    let balance: Money?

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if let balance {
                Text(balance.formatted())
                    .foregroundStyle(balance < .zero ? Color.red : Color.green)
                    .font(.caption)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Expense Row

private struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title ?? "Untitled")
                    .font(.body)
                if let date = expense.date {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let payer = expense.paidBy {
                    Text("Paid by \(payer.name ?? "?")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            Text(Money(amount: expense.amount).formatted())
                .font(.callout)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        GroupDetailView(group: PersistenceController.previewGroup)
            .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
    }
}

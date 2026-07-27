import SwiftUI
import CoreData
import DutchKit

/// Sheet for adding a new expense to a group.
struct AddExpenseView: View {
    let group: ExpenseGroup
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var amount: Double = 0
    @State private var selectedPayer: Person?
    @State private var selectedParticipants: Set<Person> = []
    @State private var errorMessage: String?

    private var store: GroupStore { GroupStore(context: context) }

    private var members: [Person] {
        (group.members as? Set<Person>)?
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                // ── Details ─────────────────────────────────────
                Section("Expense Details") {
                    TextField("Title", text: $title)

                    HStack {
                        Text("$")
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                    }
                }

                // ── Paid By ────────────────────────────────────
                Section("Paid By") {
                    if members.isEmpty {
                        Text("Add members first.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Who paid?", selection: $selectedPayer) {
                            Text("Select…").tag(nil as Person?)
                            ForEach(members, id: \.objectID) { member in
                                Text(member.name ?? "?").tag(member as Person?)
                            }
                        }
                    }
                }

                // ── Split Among ─────────────────────────────────
                Section {
                    if members.isEmpty {
                        Text("Add members first.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(members, id: \.objectID) { member in
                            MemberToggleRow(
                                name: member.name ?? "?",
                                isSelected: selectedParticipants.contains(member)
                            ) {
                                toggle(member)
                            }
                        }
                    }
                } header: {
                    Text("Split Among")
                } footer: {
                    // The payer is not added implicitly — leaving them out is
                    // how you record paying purely on someone else's behalf.
                    Text("Include whoever shares the cost. Leave the payer out if they were covering it for others.")
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save", action: saveExpense)
                        .disabled(!isValid)
                }
            }
            .onChange(of: selectedPayer) { _, newPayer in
                // Most of the time the payer also shares the expense, so
                // preselect them. They can still be toggled back off.
                if let newPayer {
                    selectedParticipants.insert(newPayer)
                }
            }
            .alert("Couldn't Save Expense", isPresented: errorBinding) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    // MARK: - Selection

    private func toggle(_ member: Person) {
        if selectedParticipants.contains(member) {
            selectedParticipants.remove(member)
        } else {
            selectedParticipants.insert(member)
        }
    }

    // MARK: - Validation

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && amount > 0
            && selectedPayer != nil
            && !selectedParticipants.isEmpty
    }

    // MARK: - Save

    private func saveExpense() {
        guard let payer = selectedPayer else { return }

        do {
            try store.addExpense(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: Money(amount: amount),
                paidBy: payer,
                splitAmong: selectedParticipants,
                in: group
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Member Row

/// Extracted so the `Form` body stays small enough for the type checker.
private struct MemberToggleRow: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        HStack {
            Text(name)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

#Preview {
    AddExpenseView(group: PersistenceController.previewGroup)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}

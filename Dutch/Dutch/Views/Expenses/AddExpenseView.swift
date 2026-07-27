import SwiftUI
import CoreData
import DutchKit

/// Sheet for adding a new expense to a group.
struct AddExpenseView: View {
    let group: ExpenseGroup
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    /// Held as text rather than a `Double` so the field can start genuinely
    /// empty. Bound to a number it showed a literal `0` that `isValid` then
    /// rejected — a form that looks filled in and refuses to save.
    @State private var amountText = ""
    @State private var selectedPayer: Person?
    @State private var selectedParticipants: Set<Person> = []
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    /// Seeds the two selections from the state the form would otherwise make
    /// the user re-enter every single time.
    ///
    /// Done in `init` rather than `.task` so the sheet is never briefly drawn
    /// with nothing selected, and so a later re-render can't re-seed over an
    /// edit in progress — `@State` keeps the value from first construction.
    init(group: ExpenseGroup) {
        self.group = group

        let roster = Self.roster(of: group)
        // Splitting across everyone is what the app is for; "nobody" was never
        // a useful starting point, and cost a tap per member to escape.
        _selectedParticipants = State(initialValue: Set(roster))
        _selectedPayer = State(initialValue: ExpenseDefaults.lastPayer(in: group, among: roster))
    }

    private var store: GroupStore { GroupStore(context: context) }

    private var members: [Person] { Self.roster(of: group) }

    private static func roster(of group: ExpenseGroup) -> [Person] {
        (group.members as? Set<Person>)?
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                paidBySection
                splitAmongSection
            }
            .scrollDismissesKeyboard(.interactively)
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
            // One haptic per change to the selection as a whole. Per-row
            // feedback would fire six times at once on "Everyone".
            .sensoryFeedback(.selection, trigger: selectedParticipants)
            .errorBanner($errorMessage)
            .task { titleFocused = true }
        }
    }

    // MARK: - Sections

    private var detailsSection: some View {
        Section {
            TextField("Title", text: $title)
                .focused($titleFocused)
                .submitLabel(.next)

            HStack {
                // Hidden from VoiceOver because the field below carries the
                // same label — otherwise it is announced twice.
                Text("Amount")
                    .accessibilityHidden(true)

                Spacer(minLength: 12)

                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                    // Without this the field's only label is its "0"
                    // placeholder, which VoiceOver reads as "zero, text field".
                    .accessibilityLabel("Amount")
                    .accessibilityHint("In \(group.currency)")

                // The group's currency, not the device's. Shown as a code
                // rather than a symbol so it stays unambiguous between the
                // currencies that share a `$` or a `kr`.
                Text(group.currency)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } header: {
            Text("Expense Details")
        } footer: {
            // Echoes back exactly what will be stored, which is the only way
            // the user can catch a mis-parsed separator before saving.
            if let amount = parsedAmount {
                Text("Saves as \(Money(amount: amount).formatted(in: group))")
                    .contentTransition(.numericText())
            }
        }
    }

    private var paidBySection: some View {
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
    }

    private var splitAmongSection: some View {
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
            HStack {
                Text("Split Among")
                Spacer()
                if !members.isEmpty {
                    // Splitting evenly across everyone is the common case, and
                    // it used to cost one tap per member.
                    Button(allSelected ? "None" : "Everyone") {
                        withAnimation(.snappy) {
                            selectedParticipants = allSelected ? [] : Set(members)
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .textCase(nil)  // section headers uppercase; the button shouldn't
                }
            }
        } footer: {
            // The payer is not added implicitly — leaving them out is
            // how you record paying purely on someone else's behalf.
            Text("Include whoever shares the cost. Leave the payer out if they were covering it for others.")
        }
    }

    // MARK: - Selection

    private var allSelected: Bool {
        !members.isEmpty && selectedParticipants.count == members.count
    }

    private func toggle(_ member: Person) {
        withAnimation(.snappy) {
            if selectedParticipants.contains(member) {
                selectedParticipants.remove(member)
            } else {
                selectedParticipants.insert(member)
            }
        }
    }

    // MARK: - Validation

    /// Accepts either decimal separator. `.decimalPad` shows whichever the
    /// device locale uses, but people type the one their keyboard muscle memory
    /// reaches for, and the pad emits no grouping separators to confuse this.
    private var parsedAmount: Double? {
        let normalized = amountText
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && parsedAmount != nil
            && selectedPayer != nil
            && !selectedParticipants.isEmpty
    }

    // MARK: - Save

    private func saveExpense() {
        guard let payer = selectedPayer, let amount = parsedAmount else { return }

        do {
            try store.addExpense(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: Money(amount: amount),
                paidBy: payer,
                splitAmong: selectedParticipants,
                in: group
            )
            ExpenseDefaults.rememberPayer(payer, in: group)
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
        // A `Button`, not a tap gesture on a shape. To VoiceOver the old row
        // was static text: no button trait, no selected state, nothing to
        // activate. The empty circle matters too — an unselected member used
        // to show nothing at all, so there was no cue the row was tappable.
        Button(action: onTap) {
            HStack {
                Text(name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 12)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    AddExpenseView(group: PersistenceController.previewGroup)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}

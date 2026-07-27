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
    /// The currency the amount is being *entered* in, which is not necessarily
    /// the one the group settles in.
    @State private var currencyCode: String
    /// Units of `currencyCode` per one unit of the group's currency. Text for
    /// the same reason `amountText` is.
    @State private var rateText: String
    @State private var selectedPayer: Person?
    @State private var selectedParticipants: Set<Person> = []
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    /// Seeds every selection from the state the form would otherwise make the
    /// user re-enter on each expense.
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

        // Mid-trip, the next expense is almost always in the same currency as
        // the last one, at the same rate. Entering ten Polish receipts should
        // cost one rate lookup, not ten.
        let currency = ExpenseDefaults.lastCurrency(in: group) ?? group.currency
        _currencyCode = State(initialValue: currency)
        _rateText = State(initialValue: Self.rateText(for: currency, in: group))
    }

    /// The remembered rate for a currency, as the text field wants it.
    ///
    /// Grouping separators are suppressed deliberately: they would come back in
    /// through `parsedRate` as a stray `4 411` and turn a prefilled rate into a
    /// silently wrong one.
    private static func rateText(for currencyCode: String, in group: ExpenseGroup) -> String {
        guard
            currencyCode != group.currency,
            let rate = ExpenseDefaults.lastRate(in: group, currencyCode: currencyCode)
        else { return "" }

        return rate.formatted(.number.precision(.fractionLength(0 ... 6)).grouping(.never))
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
            // A rate is only meaningful for the currency it was entered for, so
            // switching currency replaces it rather than carrying 4.4111 over
            // from złoty to forint — which would convert, and be wrong by two
            // orders of magnitude, with nothing on screen looking amiss.
            .onChange(of: currencyCode) { _, newCode in
                rateText = Self.rateText(for: newCode, in: group)
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

            amountRow
            currencyRow
            rateRow
        } header: {
            Text("Expense Details")
        } footer: {
            // Echoes back exactly what will be stored, which is the only way
            // the user can catch a mis-parsed separator — or a rate entered
            // upside down — before saving.
            if let summary = savesAsSummary {
                Text(summary)
                    .contentTransition(.numericText())
            }
        }
    }

    private var amountRow: some View {
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
                .accessibilityHint("In \(currencyCode)")

            // Shown as a code rather than a symbol so it stays unambiguous
            // between the currencies that share a `$` or a `kr`.
            Text(currencyCode)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// Lets an expense be entered in whatever was actually handed over, which
    /// on a trip through two countries is not the currency the group settles in.
    private var currencyRow: some View {
        Picker("Currency", selection: $currencyCode) {
            ForEach(currencyOptions, id: \.self) { code in
                Text(Self.currencyLabel(code)).tag(code)
            }
        }
        // A menu of ~150 currencies is unusable; this pushes a list instead.
        .pickerStyle(.navigationLink)
    }

    /// Only meaningful when the money wasn't the group's own currency, so it
    /// stays out of the way entirely for the ordinary single-currency group.
    @ViewBuilder
    private var rateRow: some View {
        if isForeign {
            HStack {
                Text("1 \(group.currency) =")
                    .accessibilityHidden(true)

                Spacer(minLength: 12)

                TextField("0", text: $rateText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
                    .accessibilityLabel("Exchange rate")
                    .accessibilityHint("How many \(currencyCode) to one \(group.currency)")

                Text(currencyCode)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
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

    // MARK: - Currency

    private var isForeign: Bool { currencyCode != group.currency }

    /// Built once — `commonISOCurrencyCodes` is ~150 entries and looking up a
    /// localized name per row per render would redo that work on every keystroke
    /// in the amount field.
    private static let currencyNames: [String: String] = {
        let locale = Locale.current
        return Dictionary(
            uniqueKeysWithValues: Locale.commonISOCurrencyCodes.compactMap { code in
                locale.localizedString(forCurrencyCode: code).map { (code, $0) }
            }
        )
    }()

    private static func currencyLabel(_ code: String) -> String {
        guard let name = currencyNames[code] else { return code }
        return "\(code) · \(name)"
    }

    /// The group's own currency first, then whatever is currently selected,
    /// then everything else — so the two codes actually in play on a trip sit
    /// at the top instead of being hunted for alphabetically.
    ///
    /// The selection is included explicitly so a code that isn't in the common
    /// list still has a row to match, which is what a `Picker` needs to display
    /// it at all.
    private var currencyOptions: [String] {
        var seen = Set<String>()
        return ([group.currency, currencyCode] + Locale.commonISOCurrencyCodes)
            .filter { seen.insert($0).inserted }
    }

    // MARK: - Validation

    /// Accepts either decimal separator. `.decimalPad` shows whichever the
    /// device locale uses, but people type the one their keyboard muscle memory
    /// reaches for, and the pad emits no grouping separators to confuse this.
    private static func parseDecimal(_ text: String) -> Double? {
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var parsedAmount: Double? { Self.parseDecimal(amountText) }

    /// The foreign-currency figure being entered, once it is complete enough to
    /// convert. `nil` while the rate is missing or unusable — `ForeignAmount`
    /// rejects a zero rate rather than dividing by it.
    private var foreignAmount: ForeignAmount? {
        guard isForeign, let amount = parsedAmount, let rate = Self.parseDecimal(rateText) else {
            return nil
        }
        return ForeignAmount(amount: amount, currencyCode: currencyCode, rate: rate)
    }

    /// What will actually be stored: always in the group's currency, converted
    /// exactly once, here.
    private var finalAmount: Money? {
        if isForeign { return foreignAmount?.converted }
        return parsedAmount.map(Money.init(amount:))
    }

    private var savesAsSummary: String? {
        guard let amount = finalAmount else {
            // Otherwise a foreign expense with no rate yet just leaves Save
            // greyed out with nothing on screen saying which field is missing.
            if isForeign, parsedAmount != nil {
                return "Enter the rate to convert this to \(group.currency)."
            }
            return nil
        }

        let stored = "Saves as \(amount.formatted(in: group))"
        guard let foreign = foreignAmount else { return stored }

        let rate = foreign.rate.formatted(.number.precision(.fractionLength(0 ... 6)))
        return "\(stored) · \(foreign.formatted()) at \(rate)"
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && finalAmount != nil
            && selectedPayer != nil
            && !selectedParticipants.isEmpty
    }

    // MARK: - Save

    private func saveExpense() {
        guard let payer = selectedPayer, let amount = finalAmount else { return }
        let foreign = foreignAmount

        do {
            try store.addExpense(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                paidBy: payer,
                splitAmong: selectedParticipants,
                in: group,
                paidIn: foreign
            )
            ExpenseDefaults.rememberPayer(payer, in: group)
            if let foreign {
                ExpenseDefaults.remember(foreign, in: group)
            } else {
                ExpenseDefaults.rememberHomeCurrency(in: group)
            }
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

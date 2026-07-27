import SwiftUI
import CoreData
import DutchKit

/// Sheet for adding a new expense to a group, or correcting an existing one.
///
/// One form for both, deliberately. The alternative the app used to force was
/// delete-and-re-enter, which on a shared group means everyone else watches an
/// expense vanish and reappear over CloudKit — and gives them a window in which
/// the balances are simply wrong.
struct ExpenseFormView: View {
    let group: ExpenseGroup

    /// The expense being corrected, or `nil` when adding a new one. Everything
    /// that differs between the two modes reads from this.
    private let editing: Expense?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    /// Held as text rather than a `Double` so the field can start genuinely
    /// empty. Bound to a number it showed a literal `0` that `isValid` then
    /// rejected — a form that looks filled in and refuses to save.
    @State private var amountText: String
    /// The currency the amount is being *entered* in, which is not necessarily
    /// the one the group settles in.
    @State private var currencyCode: String
    /// Units of `currencyCode` per one unit of the group's currency. Text for
    /// the same reason `amountText` is.
    @State private var rateText: String
    @State private var selectedPayer: Person?
    @State private var selectedParticipants: Set<Person> = []
    /// Weight per member, used only while `splitsEvenly` is off. A member with
    /// no entry counts as one share.
    @State private var shares: [Person: Int] = [:]
    @State private var splitsEvenly: Bool
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    /// A new expense, with every selection seeded from the state the form would
    /// otherwise make the user re-enter on each one.
    ///
    /// Done in `init` rather than `.task` so the sheet is never briefly drawn
    /// with nothing selected, and so a later re-render can't re-seed over an
    /// edit in progress — `@State` keeps the value from first construction.
    init(group: ExpenseGroup) {
        self.group = group
        self.editing = nil

        let roster = Self.roster(of: group)
        // Splitting across everyone is what the app is for; "nobody" was never
        // a useful starting point, and cost a tap per member to escape.
        _selectedParticipants = State(initialValue: Set(roster))
        _selectedPayer = State(initialValue: ExpenseDefaults.lastPayer(in: group, among: roster))
        _title = State(initialValue: "")
        _amountText = State(initialValue: "")
        _splitsEvenly = State(initialValue: true)

        // Mid-trip, the next expense is almost always in the same currency as
        // the last one, at the same rate. Entering ten Polish receipts should
        // cost one rate lookup, not ten.
        let currency = ExpenseDefaults.lastCurrency(in: group) ?? group.currency
        _currencyCode = State(initialValue: currency)
        _rateText = State(initialValue: Self.rateText(for: currency, in: group))
    }

    /// An existing expense, seeded from what was recorded rather than from the
    /// device's defaults.
    ///
    /// A foreign expense reopens in the currency it was *entered* in, not the
    /// group's. The stored `amount` is the converted figure, so showing that as
    /// the starting point would mean someone who came to fix a typo in the
    /// title saves a euro total back into a złoty field.
    init(editing expense: Expense, in group: ExpenseGroup) {
        self.group = group
        self.editing = expense

        _title = State(initialValue: expense.title ?? "")
        _selectedPayer = State(initialValue: expense.paidBy)
        _selectedParticipants = State(initialValue: (expense.splitAmong as? Set<Person>) ?? [])

        if let foreign = expense.foreignAmount {
            _currencyCode = State(initialValue: foreign.currencyCode)
            _amountText = State(initialValue: Self.decimalText(foreign.amount))
            _rateText = State(initialValue: Self.decimalText(foreign.rate, precision: 6))
        } else {
            _currencyCode = State(initialValue: group.currency)
            _amountText = State(initialValue: Self.decimalText(expense.amount))
            _rateText = State(initialValue: "")
        }

        // An expense with no stored weighting is an even split, and a uniform
        // weighting is stored as none at all — so the toggle starts on exactly
        // when there is something uneven to show.
        let weights = expense.shareWeights
        _splitsEvenly = State(initialValue: weights.isEmpty)
        _shares = State(initialValue: Self.shares(from: weights, in: group))
    }

    // MARK: - Seeding

    private var isEditing: Bool { editing != nil }

    /// Weights come back keyed by id; the form works in `Person`, which is what
    /// the rows and the selection are built from.
    private static func shares(from weights: [UUID: Int], in group: ExpenseGroup) -> [Person: Int] {
        guard !weights.isEmpty else { return [:] }

        return roster(of: group).reduce(into: [:]) { result, member in
            if let id = member.id, let weight = weights[id] {
                result[member] = weight
            }
        }
    }

    /// Formats a stored value for a text field.
    ///
    /// Grouping separators are suppressed deliberately: they would come back in
    /// through `parseDecimal` as a stray `4 411` and turn a prefilled figure
    /// into a silently wrong one.
    private static func decimalText(_ value: Double, precision: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... precision)).grouping(.never))
    }

    /// The remembered rate for a currency, as the text field wants it.
    private static func rateText(for currencyCode: String, in group: ExpenseGroup) -> String {
        guard
            currencyCode != group.currency,
            let rate = ExpenseDefaults.lastRate(in: group, currencyCode: currencyCode)
        else { return "" }

        return decimalText(rate, precision: 6)
    }

    private var store: GroupStore { GroupStore(context: context) }

    private var members: [Person] { Self.roster(of: group) }

    private static func roster(of group: ExpenseGroup) -> [Person] {
        (group.members as? Set<Person>)?
            .sorted { ($0.name ?? "") < ($1.name ?? "") } ?? []
    }

    var body: some View {
        // Taken once and passed down. Read as a computed property this would be
        // recomputed at every mention — and this form mentions it once per
        // member row, each pass sorting the sharers and re-splitting the whole
        // amount.
        let slices = slicePreview

        NavigationStack {
            Form {
                detailsSection
                paidBySection
                splitAmongSection(slices)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Expense" : "Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    // "Save" in both modes. The title above already says which
                    // one this is, and the UI tests reach for this button by
                    // name — a label that changes with the mode would make the
                    // add flow's assertions depend on state they never set.
                    Button("Save", action: save)
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
            .task {
                // Only when adding. Opening the keyboard on an edit puts a
                // cursor in a title the user most likely came to keep.
                titleFocused = !isEditing
            }
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

    private func splitAmongSection(_ slices: [Person: Money]) -> some View {
        Section {
            if members.isEmpty {
                Text("Add members first.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(members, id: \.objectID) { member in
                    MemberSplitRow(
                        name: member.name ?? "?",
                        isSelected: selectedParticipants.contains(member),
                        share: splitsEvenly ? nil : share(for: member),
                        slice: slices[member].map { $0.formatted(in: group) },
                        onTap: { toggle(member) },
                        onShareChange: { shares[member] = $0 }
                    )
                }

                // Disabled below two people because there is nothing to weight
                // — one sharer takes the whole amount at any share count.
                Toggle("Split by shares", isOn: sharesBinding)
                    .disabled(selectedParticipants.count < 2)
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
            if splitsEvenly {
                // The payer is not added implicitly — leaving them out is
                // how you record paying purely on someone else's behalf.
                Text("Include whoever shares the cost. Leave the payer out if they were covering it for others.")
            } else {
                Text("Shares are relative: 2× pays twice what 1× pays — the room two people share against the single.")
            }
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
                // Dropped rather than kept: a weight belonging to someone no
                // longer in the split would reappear from nowhere if they were
                // added back later.
                shares[member] = nil
            } else {
                selectedParticipants.insert(member)
            }
        }
    }

    private func share(for member: Person) -> Int? {
        guard selectedParticipants.contains(member) else { return nil }
        return shares[member] ?? 1
    }

    /// Turning shares off discards the weighting rather than hiding it. A
    /// weighting that is invisible but still applied is the worst of both: the
    /// form would say "even" while the balances disagreed.
    private var sharesBinding: Binding<Bool> {
        Binding(
            get: { !splitsEvenly },
            set: { wantsShares in
                withAnimation(.snappy) {
                    splitsEvenly = !wantsShares
                    if !wantsShares { shares = [:] }
                }
            }
        )
    }

    /// What each member will actually be charged, for the rows to show.
    ///
    /// Routed through `SettlementCalculator.slices` rather than divided here,
    /// so the preview and the balance it becomes are the same arithmetic down
    /// to the cent — including which member the leftover lands on.
    private var slicePreview: [Person: Money] {
        guard !splitsEvenly, let amount = finalAmount else { return [:] }

        let weights = weightsByID
        guard !weights.isEmpty else { return [:] }

        let byID = Dictionary(
            SettlementCalculator.slices(of: amount, among: weights)
                .map { ($0.participant, $0.amount) },
            uniquingKeysWith: { first, _ in first }
        )

        return selectedParticipants.reduce(into: [:]) { result, member in
            if let id = member.id, let slice = byID[id] {
                result[member] = slice
            }
        }
    }

    /// The weighting as the store and the calculator want it. Empty while the
    /// split is even, which is what leaves the stored expense unweighted.
    private var weightsByID: [UUID: Int] {
        guard !splitsEvenly else { return [:] }

        return selectedParticipants.reduce(into: [:]) { result, member in
            if let id = member.id {
                result[id] = shares[member] ?? 1
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

    private func save() {
        guard let payer = selectedPayer, let amount = finalAmount else { return }
        let foreign = foreignAmount
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let weights = weightsByID

        do {
            if let editing {
                try store.update(
                    editing,
                    title: trimmed,
                    amount: amount,
                    paidBy: payer,
                    splitAmong: selectedParticipants,
                    paidIn: foreign,
                    shares: weights
                )
            } else {
                try store.addExpense(
                    title: trimmed,
                    amount: amount,
                    paidBy: payer,
                    splitAmong: selectedParticipants,
                    in: group,
                    paidIn: foreign,
                    shares: weights
                )
                // Only when adding. An edit corrects something recorded
                // earlier — often much earlier — and letting it rewrite "the
                // last currency used" would prefill the next expense from a
                // receipt two countries ago.
                remember(payer: payer, foreign: foreign)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remember(payer: Person, foreign: ForeignAmount?) {
        ExpenseDefaults.rememberPayer(payer, in: group)
        if let foreign {
            ExpenseDefaults.remember(foreign, in: group)
        } else {
            ExpenseDefaults.rememberHomeCurrency(in: group)
        }
    }
}

// MARK: - Member Row

/// Extracted so the `Form` body stays small enough for the type checker.
private struct MemberSplitRow: View {
    let name: String
    let isSelected: Bool
    /// The member's weight, or `nil` when the split is even and no stepper
    /// should appear at all.
    let share: Int?
    /// What this member will be charged, once there is an amount to divide.
    let slice: String?
    let onTap: () -> Void
    let onShareChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            // A `Button`, not a tap gesture on a shape. To VoiceOver the old
            // row was static text: no button trait, no selected state, nothing
            // to activate. The empty circle matters too — an unselected member
            // used to show nothing at all, so there was no cue the row was
            // tappable.
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .foregroundStyle(.primary)

                        // Only with an uneven split, where "2×" on its own
                        // doesn't tell anyone what they are actually paying.
                        if isSelected, let slice {
                            Text(slice)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }

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

            if isSelected, let share {
                Stepper(
                    value: Binding(get: { share }, set: onShareChange),
                    in: 1 ... 20
                ) {
                    Text("\(share)×")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                .fixedSize()
                .accessibilityLabel("Shares for \(name)")
            }
        }
    }
}

#Preview("Add") {
    ExpenseFormView(group: PersistenceController.previewGroup)
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}

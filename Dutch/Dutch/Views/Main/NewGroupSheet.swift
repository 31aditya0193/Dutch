import SwiftUI

/// Sheet for creating a group.
///
/// This used to be an `Alert` with a `TextField` in it. Alerts can't validate,
/// can't be swiped away, and — as it was wired — let you tap "Create" on an
/// empty field and watch nothing happen. A sheet also has room for the currency,
/// which has to be decided once, at creation, before any amount is recorded.
struct NewGroupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var currencyCode = Locale.current.currency?.identifier ?? "USD"
    /// Seeded at random rather than from a fixed default, so somebody setting up
    /// three trips in a row doesn't get three identical blue tiles unless they
    /// go looking for the picker.
    @State private var appearance = GroupAppearance.random
    @FocusState private var nameFocused: Bool

    /// Called with the trimmed name, the chosen currency and the chosen look.
    let onCreate: (String, String, GroupAppearance) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The tile leads the field it names, so the thing being
                    // chosen below is already on screen next to what it labels.
                    HStack(spacing: 12) {
                        GroupIcon(appearance)

                        TextField("Group Name", text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(create)
                    }

                    Picker("Currency", selection: $currencyCode) {
                        ForEach(Self.currencies, id: \.code) { currency in
                            Text(verbatim: "\(currency.name) (\(currency.code))")
                                .tag(currency.code)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } footer: {
                    Text("Every expense in this group is recorded in this currency, on everyone's device.")
                }

                Section("Appearance") {
                    AppearancePicker(appearance: $appearance)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        // Medium keeps the list visible behind it so this reads as a quick
        // task rather than a change of screen; large is there for the currency
        // picker and for accessibility text sizes.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Apple's compose sheets put the caret in the first field on arrival.
        .task { nameFocused = true }
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        onCreate(trimmedName, currencyCode, appearance)
        dismiss()
    }

    // MARK: - Currencies

    /// Built once — deriving and sorting 150-odd localized names is not
    /// something to redo on every keystroke in the name field.
    private static let currencies: [(code: String, name: String)] = {
        let locale = Locale.current
        return Locale.commonISOCurrencyCodes
            .map { code in
                (code: code, name: locale.localizedString(forCurrencyCode: code) ?? code)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            NewGroupSheet { name, currency, appearance in
                print("create \(name) in \(currency) as \(appearance)")
            }
        }
}

import SwiftUI

/// Sheet for renaming a group and changing how it looks.
///
/// Deliberately not a currency editor. The currency is pinned when the group is
/// created because every amount recorded since has been *in* it — switching it
/// later wouldn't convert anything, it would silently reinterpret nine months of
/// receipts as if they had been paid in the new one. The footer says so, since a
/// missing control with no explanation reads as an oversight.
struct EditGroupSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var appearance: GroupAppearance

    /// Called with the trimmed name and the chosen look.
    private let onSave: (String, GroupAppearance) -> Void
    private let currencyCode: String

    init(group: ExpenseGroup, onSave: @escaping (String, GroupAppearance) -> Void) {
        _name = State(initialValue: group.name ?? "")
        // Seeded with what the row is already showing — which for a group that
        // has never been styled is its derived look, not a blank. Opening the
        // sheet on the icon you were just looking at is the whole reason the
        // derivation is stable.
        _appearance = State(initialValue: group.appearance)
        self.currencyCode = group.currency
        self.onSave = onSave
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        GroupIcon(appearance)

                        TextField("Group Name", text: $name)
                            .submitLabel(.done)
                            .onSubmit(save)
                    }
                } footer: {
                    Text("Recorded in \(currencyCode), fixed when the group was created.")
                }

                Section("Appearance") {
                    AppearancePicker(appearance: $appearance)
                }
            }
            .navigationTitle("Edit Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        onSave(trimmedName, appearance)
        dismiss()
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            EditGroupSheet(group: PersistenceController.previewGroup) { name, appearance in
                print("save \(name) as \(appearance)")
            }
        }
}

import SwiftUI

/// Sheet for adding one person to a group.
///
/// Kept deliberately small — a single field at a short detent, so the members
/// list stays visible behind it and adding three people in a row doesn't feel
/// like three screen changes.
struct AddMemberSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @FocusState private var nameFocused: Bool

    let onAdd: (String) -> Void

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .textContentType(.givenName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit(add)
            }
            .navigationTitle("Add Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.height(200), .medium])
        .presentationDragIndicator(.visible)
        .task { nameFocused = true }
    }

    private func add() {
        guard !trimmedName.isEmpty else { return }
        onAdd(trimmedName)
        dismiss()
    }
}

#Preview {
    Text("Behind the sheet")
        .sheet(isPresented: .constant(true)) {
            AddMemberSheet { print("add \($0)") }
        }
}

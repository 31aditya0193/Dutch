import CoreData
import SwiftUI

/// Main screen showing all expense groups — both the user's own and any that
/// have been shared with them.
struct GroupListView: View {
    @Environment(\.managedObjectContext) private var context

    /// Reads go through `@FetchRequest` so changes synced down from CloudKit
    /// refresh the list on their own, with no manual reload.
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\ExpenseGroup.creationDate, order: .reverse)],
        animation: .default
    )
    private var groups: FetchedResults<ExpenseGroup>

    @State private var showingNewGroup = false
    @State private var showingJoinGroup = false
    @State private var newGroupName = ""
    @State private var errorMessage: String?

    private var store: GroupStore { GroupStore(context: context) }

    var body: some View {
        NavigationStack {
            List {
                if groups.isEmpty {
                    ContentUnavailableView {
                        Label("No Groups", systemImage: "rectangle.3.group")
                    } description: {
                        Text("Create a group to start splitting expenses, or join one with a QR code.")
                    }
                } else {
                    ForEach(groups) { group in
                        NavigationLink {
                            GroupDetailView(group: group)
                        } label: {
                            GroupRow(group: group)
                        }
                    }
                    .onDelete(perform: delete)
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
            .alert("New Group", isPresented: $showingNewGroup) {
                TextField("Group Name", text: $newGroupName)
                Button("Cancel", role: .cancel) { newGroupName = "" }
                Button("Create", action: createGroup)
            } message: {
                Text("Enter a name for your new expense group.")
            }
            .sheet(isPresented: $showingJoinGroup) {
                JoinGroupView()
            }
            .alert("Something Went Wrong", isPresented: errorBinding) {
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

    // MARK: - Actions

    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        newGroupName = ""
        guard !trimmed.isEmpty else { return }

        do {
            try store.createGroup(named: trimmed)
        } catch {
            errorMessage = error.localizedDescription
        }
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
    @ObservedObject var group: ExpenseGroup

    var body: some View {
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

            if let sequence = group.wordSequence {
                Text(sequence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }

            HStack {
                Label("\(group.members?.count ?? 0)", systemImage: "person")
                Label("\(group.expenses?.count ?? 0)", systemImage: "receipt")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    GroupListView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}

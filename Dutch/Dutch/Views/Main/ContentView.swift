import SwiftUI

/// Root view. The managed object context arrives from `DutchApp`, and
/// `GroupListView` reads it through `@FetchRequest`.
struct ContentView: View {
    var body: some View {
        GroupListView()
    }
}

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}

import AppIntents
import CoreData

/// A group, as the rest of the system sees it.
///
/// A value snapshot rather than a wrapper around the managed object. App
/// Intents hands these across process boundaries and holds onto them between
/// runs — a Shortcut saved today names a group and runs next week — so nothing
/// here may be tied to a context. The `id` is what survives; everything else is
/// what it looked like when the snapshot was taken.
struct GroupEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Group" }
    static var defaultQuery = GroupQuery()

    let id: UUID
    let name: String
    /// The `green-moon-tea` label, kept so it can be shown under the name and
    /// searched for. A label, never a credential — see `WordGenerator`.
    let wordSequence: String?

    /// Name over word sequence: the name is what anyone calls the trip, and the
    /// sequence is how two people confirm they joined the same one. Both matter
    /// in a picker showing several groups whose names could be similar.
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: wordSequence.map { "\($0)" }
        )
    }
}

extension GroupEntity {
    /// `nil` for a record too incomplete to name — every attribute is optional
    /// for CloudKit's sake, so a half-synced group is representable. Offering
    /// one in a picker would mean a Shortcut pinned to a group with no id.
    init?(_ group: ExpenseGroup) {
        guard let id = group.id, let name = group.name else { return nil }
        self.id = id
        self.name = name
        self.wordSequence = group.wordSequence
    }
}

// MARK: - Query

/// How the system finds groups: by id when re-running a saved shortcut, by name
/// or word sequence when someone speaks or types one, and newest-first when
/// filling a picker.
///
/// `EntityStringQuery` is what makes "add sixty to green-moon-tea" resolve. It
/// searches groups already on this device; a sequence naming a group that was
/// never shared with this iCloud account finds nothing, which is the only
/// correct answer — the word sequence has never been what grants access.
struct GroupQuery: EntityQuery, EntityStringQuery {
    /// Intents perform on the main actor and read the view context, so this
    /// does too. See `AddExpenseIntent` for why that is the whole concurrency
    /// story for this feature.
    @MainActor
    private var context: NSManagedObjectContext {
        PersistenceController.shared.viewContext
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [GroupEntity] {
        identifiers
            .compactMap { GroupLookup.group(id: $0, in: context) }
            .compactMap(GroupEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [GroupEntity] {
        GroupLookup.groups(matching: string, in: context).compactMap(GroupEntity.init)
    }

    /// Newest first, matching the group list. The trip somebody wants to add an
    /// expense to is almost always the one they are on.
    @MainActor
    func suggestedEntities() async throws -> [GroupEntity] {
        GroupLookup.all(in: context).compactMap(GroupEntity.init)
    }
}

import Foundation

/// Remembers, per group, who paid for the last expense entered *on this device*.
///
/// Deliberately `UserDefaults` and not an attribute on the group: this must not
/// sync. The assumption it encodes is that each person enters their own
/// spending on their own phone, so "who usually pays" is a fact about the
/// device, not about the group. Stored on the shared record instead, a partner
/// logging an expense they paid for would travel over CloudKit and flip the
/// default on everyone else's phone — the exact opposite of the intent.
enum ExpenseDefaults {
    private static let store = UserDefaults.standard

    private static func key(for group: ExpenseGroup) -> String? {
        group.id.map { "lastPayer.\($0.uuidString)" }
    }

    /// The remembered payer, if they are still a member of the group.
    ///
    /// Resolved against the roster rather than fetched, so a payer who has
    /// since been removed simply yields `nil` and the picker opens unset.
    static func lastPayer(in group: ExpenseGroup, among members: [Person]) -> Person? {
        guard
            let key = key(for: group),
            let stored = store.string(forKey: key),
            let id = UUID(uuidString: stored)
        else { return nil }

        return members.first { $0.id == id }
    }

    static func rememberPayer(_ payer: Person, in group: ExpenseGroup) {
        guard let key = key(for: group), let id = payer.id else { return }
        store.set(id.uuidString, forKey: key)
    }

    /// Drops a deleted group's entry, so the keys don't accumulate for groups
    /// that no longer exist.
    static func forget(_ group: ExpenseGroup) {
        guard let key = key(for: group) else { return }
        store.removeObject(forKey: key)
    }
}

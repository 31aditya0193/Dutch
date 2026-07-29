/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import DutchKit

/// Finding a group from outside the view tree.
///
/// The app's screens read through `@FetchRequest` and never fetch by hand —
/// see `GroupStore` for why. Intents and the scene delegate have no view to
/// hang a fetch request on, and they want one answer once rather than a live
/// result set, so they come here instead. This is the only place in the app
/// that fetches groups imperatively, which is what keeps that exception
/// visible.
enum GroupLookup {
    static func group(id: UUID, in context: NSManagedObjectContext) -> ExpenseGroup? {
        let request = ExpenseGroup.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// The group the user last opened, if it is still around.
    static func lastOpened(in context: NSManagedObjectContext) -> ExpenseGroup? {
        ExpenseDefaults.lastOpenedGroupID.flatMap { group(id: $0, in: context) }
    }

    /// Every group, newest first — the order the list shows them in.
    ///
    /// Feeds the Shortcuts picker, where the group somebody wants to add an
    /// expense to is overwhelmingly the trip they are on right now.
    static func all(in context: NSManagedObjectContext) -> [ExpenseGroup] {
        let request = ExpenseGroup.fetchRequest()
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ExpenseGroup.creationDate, ascending: false)
        ]
        return (try? context.fetch(request)) ?? []
    }

    /// Groups whose name or word sequence matches what somebody said or typed.
    ///
    /// Both, because both are names people use for the same thing: "Berlin
    /// Trip" is what it is called and "green-moon-tea" is what is printed next
    /// to the QR code. Matching only the first would make the sequence a label
    /// you can read out but not act on.
    ///
    /// The sequence is compared through `WordGenerator.normalised`, so
    /// "green moon tea" — which is how Siri hears it, and how anyone typing it
    /// from a printout is likely to write it — matches the stored
    /// "green-moon-tea".
    ///
    /// Matching a sequence still grants nothing. Access comes only from the
    /// CloudKit share; this searches groups the device already has, and a
    /// sequence naming a group it doesn't have finds nothing at all.
    static func groups(
        matching text: String,
        in context: NSManagedObjectContext
    ) -> [ExpenseGroup] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sequence = WordGenerator.normalised(trimmed)

        let request = ExpenseGroup.fetchRequest()
        // `CONTAINS[cd]` on the name so "berlin" finds "Berlin Trip", and an
        // exact match on the sequence, which is a whole identifier rather than
        // a phrase — a partial one would match several groups at random.
        request.predicate = NSPredicate(
            format: "name CONTAINS[cd] %@ OR wordSequence ==[c] %@",
            trimmed,
            sequence
        )
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \ExpenseGroup.creationDate, ascending: false)
        ]
        return (try? context.fetch(request)) ?? []
    }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import AppIntents
import CoreData

/// What an intent can't do, said in a sentence Siri can read out.
///
/// `CustomLocalizedStringResourceConvertible` is the part that matters:
/// without it the system reports a generic failure, and an intent that quietly
/// does nothing is worse than one that says why. Every case here names the fix,
/// because the person hearing it is holding a phone and can act on it.
enum DutchIntentError: Error, CustomLocalizedStringResourceConvertible {
    /// No group was given and none has been opened yet.
    case noGroupChosen
    /// A saved shortcut names a group this device no longer has.
    case unknownGroup
    /// The group has nobody to charge.
    case noMembers(group: String)
    /// The device hasn't been told which member is holding it, so there is
    /// nobody to record as having paid.
    case noIdentity(group: String)
    case saveFailed(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noGroupChosen:
            "Choose a group. Dutch will remember the last one you opened."
        case .unknownGroup:
            "That group isn't on this device."
        case .noMembers(let group):
            "\(group) has no members yet. Add one in Dutch first."
        case .noIdentity(let group):
            // Names the exact gesture, because it is a touch-and-hold on a row
            // and nothing on screen advertises it after the first time.
            "Dutch doesn't know which member you are in \(group). Open the group and touch and hold your own name."
        case .saveFailed(let reason):
            "Dutch couldn't save that: \(reason)"
        }
    }
}

// MARK: - Resolving a group

extension AppIntent {
    /// The group an intent should act on: the one that was asked for, the one
    /// last opened, or — failing both — the only one there is.
    ///
    /// The fallbacks are the reason these intents are worth having. "Add an
    /// expense" said to a phone in the middle of a trip means *this* trip, and
    /// requiring the group to be named every time turns a five-second entry
    /// into a conversation. The single-group case matters most on a phone that
    /// has just installed the app: there is nothing to disambiguate, so asking
    /// would be asking for the sake of it.
    @MainActor
    func resolveGroup(
        _ entity: GroupEntity?,
        in context: NSManagedObjectContext
    ) throws -> ExpenseGroup {
        if let entity {
            guard let group = GroupLookup.group(id: entity.id, in: context) else {
                throw DutchIntentError.unknownGroup
            }
            return group
        }

        if let group = GroupLookup.lastOpened(in: context) { return group }

        let all = GroupLookup.all(in: context)
        guard all.count == 1, let only = all.first else {
            throw DutchIntentError.noGroupChosen
        }
        return only
    }
}

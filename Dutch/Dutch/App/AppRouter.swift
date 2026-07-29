/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation

/// Where something outside the view tree wants the app to be.
///
/// This is not a view model, and the app still has none. It is app-level
/// navigation state, and it exists because SwiftUI offers no way for code
/// running outside a view — an App Intent, the scene delegate handling a Home
/// Screen quick action — to push a screen. `GroupListView` owns the navigation
/// path; this is how anything that isn't a view asks it to move.
///
/// Destinations carry ids rather than `ExpenseGroup`s deliberately. A managed
/// object is tied to the context that fetched it and is not `Sendable`; parking
/// one in a singleton would outlive whatever assumptions its owner made. The
/// views resolve the id against their own context, which is the only place a
/// group is guaranteed to be valid.
///
/// Consumed and cleared by the view that acts on it, so a destination never
/// fires twice — coming back to the group list must not push it again.
@MainActor
@Observable
final class AppRouter {
    enum Destination: Equatable {
        /// Open a group.
        case group(UUID)
        /// Open a group and start entering an expense in it.
        case newExpense(in: UUID)

        /// The group either destination lands on.
        var groupID: UUID {
            switch self {
            case .group(let id), .newExpense(let id): id
            }
        }
    }

    /// A singleton because an intent has nothing to be handed one by. Reading
    /// and writing it is confined to the main actor, which is also where every
    /// intent in this app performs.
    static let shared = AppRouter()

    var destination: Destination?

    private init() {}

    /// Records a destination, if there is a group to point it at.
    ///
    /// Takes the optional so the call sites — which all start from
    /// `ExpenseDefaults.lastOpenedGroupID` or an intent parameter — don't each
    /// repeat the same unwrap. A `nil` id means "no group in mind", and the app
    /// opens on the list, which is the right answer for a first launch.
    func open(_ destination: Destination?) {
        guard let destination else { return }
        self.destination = destination
    }
}

/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Publishes the user's groups to Spotlight, so a trip is reachable from the
/// home screen without opening the app first.
///
/// Groups only, deliberately. An expense has nowhere of its own to open — there
/// is no expense screen, so every hit could only land on its group — and titles
/// like "Dinner" or "Taxi" repeat across every trip somebody has ever taken,
/// which turns one useful result into forty indistinguishable ones. Groups are
/// few, individually named, and each one *is* a destination.
///
/// The whole set is rewritten on every change rather than diffed. That sounds
/// wasteful and isn't: a device holds a handful of groups, and the alternative
/// is remembering which identifiers were written last time in order to work out
/// which to delete — bookkeeping that lives outside Core Data and would drift
/// from it the first time a save failed halfway. Clearing by domain identifier
/// means the index cannot hold a group that no longer exists, whatever
/// happened.
@MainActor
final class SpotlightIndexer {
    static let shared = SpotlightIndexer()

    /// Tags every item this type writes, so one call can clear all of them.
    private static let domainIdentifier = "net.smigi.Dutch.group"

    /// How long a burst of changes is given to settle before reindexing.
    ///
    /// CloudKit delivers one sync as a run of remote-change notifications
    /// rather than a single one, so reindexing on each would rewrite the index
    /// a dozen times over for one pull.
    private static let coalescingDelay = Duration.milliseconds(500)

    private let index = CSSearchableIndex.default()

    /// Held so the reindex can fetch. Handed in rather than reached for, like
    /// `IntentWriter`, so this can be exercised without the shared stack.
    private var context: NSManagedObjectContext?

    private var pending: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    private init() {}

    // MARK: - Lifecycle

    /// Starts watching for changes and indexes what is already there.
    ///
    /// Does nothing under `-uitesting-reset`: the UI tests run against a
    /// throwaway in-memory store, and their fixtures have no business reaching
    /// the device's real Spotlight index — where they would outlive the run
    /// that created them.
    func start(reading context: NSManagedObjectContext) {
        guard observers.isEmpty else { return }
        guard !ProcessInfo.processInfo.arguments.contains("-uitesting-reset") else { return }

        self.context = context

        // Both notifications, because neither is a superset of the other: a
        // group created on this device never produces a remote change, and one
        // deleted on another device never produces a save here. Watching only
        // saves is the same mistake `@FetchRequest` exists to avoid — the index
        // would simply stop tracking anything that arrived over CloudKit.
        for name in [Notification.Name.NSManagedObjectContextDidSave,
                     .NSPersistentStoreRemoteChange] {
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { _ in
                Task { @MainActor in SpotlightIndexer.shared.scheduleReindex() }
            }
            observers.append(token)
        }

        scheduleReindex()
    }

    private func scheduleReindex() {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled else { return }
            await self?.reindex()
        }
    }

    private func reindex() async {
        guard let context else { return }

        let items = GroupLookup.all(in: context).compactMap(Self.searchableItem)

        do {
            try await index.deleteSearchableItems(
                withDomainIdentifiers: [Self.domainIdentifier]
            )
            try await index.indexSearchableItems(items)
        } catch {
            // Spotlight is a way in, never the only one, and a failure here
            // costs a search result rather than any data. Logged rather than
            // surfaced: there is nothing the person holding the phone could do
            // about it, and the next save or sync tries again anyway.
            print("[Dutch] Spotlight indexing failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Items

    /// `nil` for a group too incomplete to name, exactly as `GroupEntity` is —
    /// every attribute is optional for CloudKit's sake, so a half-synced group
    /// is representable and would otherwise index as an untitled row that
    /// opens nothing.
    private static func searchableItem(for group: ExpenseGroup) -> CSSearchableItem? {
        guard let id = group.id, let name = group.name else { return nil }

        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = name
        attributes.displayName = name

        // Reading the relationship directly is fine here and is not fine in a
        // view — see `GroupContentsRequests`. Nothing is being observed: this
        // refetches the world on every change, so there is no stale set to be
        // caught holding.
        let members = ((group.members as? Set<Person>) ?? [])
            .compactMap(\.name)
            .sorted()

        // The sequence first, because that is what distinguishes two trips
        // somebody named "Skiing"; the roster after it, because that is what
        // people actually remember about a group they haven't opened in weeks.
        attributes.contentDescription = [group.wordSequence, members.joined(separator: ", ")]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")

        // Member names are searchable but the sequence's individual words are
        // not: "green" would match every trip that happened to draw that word,
        // and the sequence is only ever used whole. It is still a label and not
        // a credential — finding it here searches groups this device already
        // has, and access comes only from the CloudKit share.
        attributes.keywords = [name] + members + [group.wordSequence].compactMap { $0 }

        let item = CSSearchableItem(
            uniqueIdentifier: id.uuidString,
            domainIdentifier: domainIdentifier,
            attributeSet: attributes
        )
        // Items expire after a month by default. A trip that syncs no changes
        // and isn't opened would quietly fall out of Spotlight — which is
        // precisely the group somebody would go looking for this way.
        item.expirationDate = .distantFuture

        return item
    }

    // MARK: - Opening

    /// Routes a tapped Spotlight result, if it is one this app wrote.
    ///
    /// Lands on the group rather than on a new expense: the search term was the
    /// group's name, so opening it is what was asked for. `NewExpenseIntent`
    /// and the Home Screen action are how somebody says they want to add
    /// something.
    static func handle(_ activity: NSUserActivity) {
        guard activity.activityType == CSSearchableItemActionType,
              let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
              let id = UUID(uuidString: identifier)
        else { return }

        AppRouter.shared.open(.group(id))
    }
}

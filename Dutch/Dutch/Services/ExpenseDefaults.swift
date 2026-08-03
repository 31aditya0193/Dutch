/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import Foundation
import DutchKit

/// Per-group state belonging to *this device* rather than to the group: who
/// usually pays, which currency and rate the last expense used, and which
/// member the person holding the phone is.
///
/// Deliberately `UserDefaults` and not attributes on the group: none of this
/// must sync. The assumption it encodes is that each person enters their own
/// spending on their own phone, so "who usually pays" is a fact about the
/// device, not about the group. Stored on the shared record instead, a partner
/// logging an expense they paid for would travel over CloudKit and flip the
/// default on everyone else's phone — the exact opposite of the intent. The
/// same goes double for identity: "I am Marek" is true on exactly one device,
/// and syncing it would tell everyone in the group that they are Marek too.
///
/// None of it is authoritative. Nothing here feeds a balance — these are
/// prefills and labels — so a stale value costs a correction, never a wrong
/// number.
enum ExpenseDefaults {
    /// The app group suite rather than `.standard`, for the same reason the
    /// Core Data stores moved there: a second process on this device — the
    /// widget on the roadmap — has its own `.standard` and would see none of
    /// this. Identity in particular is what lets a widget say "you owe" rather
    /// than reporting the group's total, which is the whole point of it.
    private static let store = PersistenceController.appGroupDefaults

    /// Posted when `me(in:among:)` would answer differently than it just did.
    ///
    /// Views that show identity need to hear about it, and `UserDefaults` is not
    /// observable. The obvious substitute — `UserDefaults.didChangeNotification`
    /// — is a firehose: it carries every write to the suite, and `CloudSyncMonitor`
    /// stamps `lastSync` into this very suite on every successful import. Rows
    /// listening on it therefore re-resolved identity once per sync, forever,
    /// for a value that had not moved. Filtering by `object:` would not have
    /// helped, because that is the same suite.
    ///
    /// This says the one thing the listeners actually asked about.
    static let identityDidChange = Notification.Name("ExpenseDefaults.identityDidChange")

    /// The key prefixes, in one place, because `forget(_:)` has to be able to
    /// clear everything this type writes.
    private enum Namespace: String, CaseIterable {
        case payer = "lastPayer"
        case currency = "lastCurrency"
        /// Rates carry a further `.<currencyCode>` suffix — see `rateKey`.
        case rate = "rate"
        case identity = "identity"

        func key(for id: UUID) -> String { "\(rawValue).\(id.uuidString)" }
    }

    /// Which group the user was last looking at.
    ///
    /// The one key here that isn't per-group, so it sits outside `Namespace`:
    /// it names a group rather than describing one. It exists so that "add an
    /// expense" can mean something without a group being said out loud — from
    /// the Action button, from the Home Screen icon, or from Siri — which is
    /// the difference between a five-second entry and a conversation.
    private static let lastOpenedGroupKey = "lastOpenedGroup"

    private static func payerKey(for group: ExpenseGroup) -> String? {
        group.id.map(Namespace.payer.key(for:))
    }

    private static func currencyKey(for group: ExpenseGroup) -> String? {
        group.id.map(Namespace.currency.key(for:))
    }

    /// Rates are kept per currency, not just per group, so a trip through three
    /// countries doesn't overwrite one rate with the next. Coming back to
    /// Poland after a week in Hungary still finds the złoty rate.
    private static func rateKey(for group: ExpenseGroup, currencyCode: String) -> String? {
        group.id.map { "\(Namespace.rate.key(for: $0)).\(currencyCode)" }
    }

    // MARK: - Payer

    /// The remembered payer, if they are still a member of the group.
    ///
    /// Resolved against the roster rather than fetched, so a payer who has
    /// since been removed simply yields `nil` and the picker opens unset.
    static func lastPayer(in group: ExpenseGroup, among members: [Person]) -> Person? {
        guard
            let key = payerKey(for: group),
            let stored = store.string(forKey: key),
            let id = UUID(uuidString: stored)
        else { return nil }

        return members.first { $0.id == id }
    }

    static func rememberPayer(_ payer: Person, in group: ExpenseGroup) {
        guard let key = payerKey(for: group), let id = payer.id else { return }
        store.set(id.uuidString, forKey: key)
    }

    // MARK: - Currency

    /// The currency the last expense was entered in, which on a trip is
    /// overwhelmingly the one the next expense will use too.
    static func lastCurrency(in group: ExpenseGroup) -> String? {
        currencyKey(for: group).flatMap { store.string(forKey: $0) }
    }

    /// The rate last used for this currency in this group.
    ///
    /// Returns `nil` rather than `0` for an unseen currency: zero is a rate
    /// that cannot convert anything, and the form needs to tell "never entered"
    /// apart from a value it could prefill.
    static func lastRate(in group: ExpenseGroup, currencyCode: String) -> Double? {
        guard
            let key = rateKey(for: group, currencyCode: currencyCode),
            store.object(forKey: key) != nil
        else { return nil }

        let rate = store.double(forKey: key)
        return rate > 0 ? rate : nil
    }

    static func remember(_ foreign: ForeignAmount, in group: ExpenseGroup) {
        if let key = currencyKey(for: group) {
            store.set(foreign.currencyCode, forKey: key)
        }
        if let key = rateKey(for: group, currencyCode: foreign.currencyCode) {
            store.set(foreign.rate, forKey: key)
        }
    }

    /// Records that the last expense was entered in the group's own currency,
    /// so the picker stops offering the foreign one once the trip is over.
    static func rememberHomeCurrency(in group: ExpenseGroup) {
        guard let key = currencyKey(for: group) else { return }
        store.removeObject(forKey: key)
    }

    // MARK: - Identity

    private static func identityKey(for group: ExpenseGroup) -> String? {
        group.id.map(Namespace.identity.key(for:))
    }

    /// Which member of this group is the person holding the phone.
    ///
    /// Resolved against the roster like `lastPayer`, so an identity that was
    /// since removed from the group yields `nil` and the screens fall back to
    /// naming everyone in the third person — which is what they did before any
    /// of this existed.
    static func me(in group: ExpenseGroup, among members: [Person]) -> Person? {
        guard
            let key = identityKey(for: group),
            let stored = store.string(forKey: key),
            let id = UUID(uuidString: stored)
        else { return nil }

        return members.first { $0.id == id }
    }

    /// Sets, or with `nil` clears, who this device belongs to in the group.
    static func rememberMe(_ person: Person?, in group: ExpenseGroup) {
        guard let key = identityKey(for: group) else { return }

        defer { NotificationCenter.default.post(name: identityDidChange, object: nil) }

        guard let id = person?.id else {
            store.removeObject(forKey: key)
            return
        }
        store.set(id.uuidString, forKey: key)
    }

    // MARK: - Last opened

    /// The group the user most recently opened, if it still exists.
    ///
    /// Returns the raw id rather than resolving it: the callers that want this
    /// are intents and the scene delegate, which have no fetched roster to
    /// resolve against and would each have to fetch anyway. `GroupLookup` turns
    /// it into a group.
    static var lastOpenedGroupID: UUID? {
        store.string(forKey: lastOpenedGroupKey).flatMap(UUID.init(uuidString:))
    }

    static func rememberOpened(_ group: ExpenseGroup) {
        guard let id = group.id else { return }
        store.set(id.uuidString, forKey: lastOpenedGroupKey)
    }

    // MARK: - Cleanup

    /// Drops a deleted group's entries, so the keys don't accumulate for groups
    /// that no longer exist.
    ///
    /// Matched by prefix rather than by exact key, because the rate entries
    /// carry a currency suffix and there is no list of which ones a group
    /// accumulated.
    static func forget(_ group: ExpenseGroup) {
        guard let id = group.id else { return }

        let prefixes = Namespace.allCases.map { $0.key(for: id) }
        for key in store.dictionaryRepresentation().keys
        where prefixes.contains(where: key.hasPrefix) {
            store.removeObject(forKey: key)
        }

        // Separately, because this key holds an id rather than being keyed by
        // one. Left behind it would point the Action button and the Home Screen
        // action at a group that no longer exists, which is a launch into
        // nothing rather than a stale prefill.
        if lastOpenedGroupID == id {
            store.removeObject(forKey: lastOpenedGroupKey)
        }

        // The row for this group is on its way out, so nothing on screen is
        // waiting for this. Posted anyway, because "identity may have changed"
        // is true and a listener that has to know *which* group was forgotten
        // to decide whether to care is a listener coupled to this method.
        NotificationCenter.default.post(name: identityDidChange, object: nil)
    }
}

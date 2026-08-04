/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CloudKit
import Foundation

/// Which iCloud account this device is signed in to, as CloudKit names it.
///
/// One string: the record name of the user's record in the app's container. It
/// is stable for an Apple ID and identical on every device that Apple ID is
/// signed in to, which is the whole reason this works — a member claimed on a
/// phone resolves by itself on the same person's iPad.
///
/// This is deliberately *not* the same idea as `ExpenseDefaults.me`, and the two
/// answer different questions. `ExpenseDefaults` says "on this device, I am the
/// member called Marek" — a fact about the device, which is why it must never
/// sync. `Person.cloudUserRecordName` says "this member is the Apple ID
/// ending 4F2" — a fact about the *group*, true for everyone looking at it, and
/// so it syncs like any other attribute. Identity then falls out of comparing
/// the two: the synced link says who each member is, and this says which one of
/// them is me. Nothing device-specific ever leaves the phone.
///
/// Not actor-isolated, unlike most services here. Everything it touches is
/// already safe from any thread — `UserDefaults` is, and `userRecordID()` is
/// async and has no opinion about where it is awaited — and isolating it would
/// mean `GroupStore` and the App Intents, neither of which is on the main
/// actor, could not ask who is signed in.
enum CloudIdentity {

    /// Cached in the app group rather than held in memory, because
    /// `ExpenseDefaults.me` is synchronous and is called from App Intents,
    /// which get one shot and no opportunity to await a round trip to CloudKit.
    /// Same bargain as `PurchaseStore`: start from what was true last launch,
    /// and correct it as soon as the real answer arrives.
    private static let cacheKey = "cloudUserRecordName"

    private static var store: UserDefaults { PersistenceController.appGroupDefaults }

    /// The signed-in account, or `nil` when nobody is signed in — or when the
    /// first `refresh()` of the app's life hasn't returned yet.
    ///
    /// A `nil` here is not an error and must not be treated as one. It means
    /// only "no link can be resolved right now", and every caller falls back to
    /// the device-local identity, which is exactly what the app did before any
    /// of this existed.
    static var current: String? {
        store.string(forKey: cacheKey)
    }

    /// Asks CloudKit who is signed in, and caches the answer.
    ///
    /// Signing out has to clear the cache, not just fail to update it. Left
    /// behind, the old record name would keep resolving a member as "you" for
    /// somebody who has since signed in as a different Apple ID — the one case
    /// where a stale identity says something actively false rather than merely
    /// out of date.
    static func refresh() async {
        let container = CKContainer(identifier: PersistenceController.cloudKitContainerIdentifier)

        do {
            let recordID = try await container.userRecordID()
            store.set(recordID.recordName, forKey: cacheKey)
        } catch {
            // Signed out, offline, or the account is temporarily unavailable.
            // Only the first is worth clearing for, and CloudKit distinguishes
            // it: `.notAuthenticated` means no account, where a network error
            // means we simply don't know yet and last launch's answer is still
            // the best one available.
            if let ckError = error as? CKError, ckError.code == .notAuthenticated {
                store.removeObject(forKey: cacheKey)
            }
        }
    }

    /// Whether a member is this device's own Apple ID.
    static func isMe(_ person: Person) -> Bool {
        guard let current, let linked = person.cloudUserRecordName else { return false }
        return current == linked
    }

    /// Whether a member is linked to somebody *else's* Apple ID, which is what
    /// makes claiming them a mistake rather than a correction.
    static func isSomeoneElse(_ person: Person) -> Bool {
        guard let linked = person.cloudUserRecordName else { return false }
        return linked != current
    }

    // MARK: - Who has joined

    /// People who have accepted the group's invitation but are not linked to any
    /// member yet.
    ///
    /// This is the half that claiming alone cannot show. A person who scanned
    /// the QR code and never opened the roster is, on everyone else's screen,
    /// indistinguishable from a name somebody typed in — so the group looks
    /// complete while somebody is missing from it, and the first sign of trouble
    /// is a balance nobody recognises.
    ///
    /// Named rather than merely counted, because "somebody has joined" is not
    /// something the owner can act on and "Bartek has joined" is: they know to
    /// tell Bartek to pick his name.
    ///
    /// Reads the locally cached share, so it costs no network and returns an
    /// empty list for a group that was never shared.
    @MainActor
    static func unclaimedJoiners(in group: ExpenseGroup) -> [String] {
        guard let share = try? CloudSharingService.existingShare(for: group) else { return [] }

        let joined = share.participants
            // Everyone invited, minus the ones who haven't said yes: a pending
            // invitation is not somebody missing from the roster, it is somebody
            // who has not arrived.
            .filter { $0.acceptanceStatus == .accepted }
            .compactMap { participant -> (id: String, name: String)? in
                guard let id = participant.userIdentity.userRecordID?.recordName else { return nil }
                return (id, displayName(for: participant.userIdentity))
            }

        let members = (group.members as? Set<Person>).map(Array.init) ?? []
        let unmatched = Set(unmatchedRecordNames(joined.map(\.id), against: members))

        return joined.filter { unmatched.contains($0.id) }.map(\.name)
    }

    /// Which of `joined` belongs to nobody on the roster.
    ///
    /// Split out from the CloudKit call so it can be tested with plain strings —
    /// `CKShare.Participant` has no public initialiser, so the alternative is
    /// not testing this at all.
    ///
    /// The current user is dropped whether or not they have claimed anyone.
    /// Telling somebody that *they* have joined but not picked a name is both
    /// obvious and already said, better, by the hint under the member list.
    static func unmatchedRecordNames(_ joined: [String], against members: [Person]) -> [String] {
        let claimed = Set(members.compactMap(\.cloudUserRecordName))
        return joined.filter { $0 != current && !claimed.contains($0) }
    }

    /// What to call a participant.
    ///
    /// CloudKit gives a name only when the account is discoverable, so the
    /// fallbacks matter: the invitation was sent to an address or a number, and
    /// either names the person better than "Someone" does.
    private static func displayName(for identity: CKUserIdentity) -> String {
        if let components = identity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        return identity.lookupInfo?.emailAddress
            ?? identity.lookupInfo?.phoneNumber
            ?? String(localized: "Someone")
    }
}

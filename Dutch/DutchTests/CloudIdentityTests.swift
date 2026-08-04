/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import Testing
@testable import Dutch

/// Covers how a synced iCloud link and a device-local identity combine.
///
/// The interesting cases are all disagreements — the link saying one thing and
/// the local key another — because those are the ones that put a "You" badge on
/// the wrong row, and none of them is visible without two accounts and two
/// devices to try it on.
@MainActor
@Suite("Cloud identity")
struct CloudIdentityTests {

    /// The real app-group suite, which these tests write to and then put back.
    ///
    /// `CloudIdentity` reads its cache through `PersistenceController`, so there
    /// is no seam to inject a fake one through and pretending otherwise would
    /// mean testing a different code path than the app runs.
    private static func withIdentity<T>(_ recordName: String?, _ body: () throws -> T) rethrows -> T {
        let store = PersistenceController.appGroupDefaults
        let key = "cloudUserRecordName"
        let previous = store.string(forKey: key)
        defer {
            if let previous { store.set(previous, forKey: key) } else { store.removeObject(forKey: key) }
        }

        if let recordName { store.set(recordName, forKey: key) } else { store.removeObject(forKey: key) }
        return try body()
    }

    private static func makeGroup(
        members names: [String],
        in context: NSManagedObjectContext
    ) throws -> (ExpenseGroup, [Person]) {
        let store = GroupStore(context: context)
        let group = try store.createGroup(named: "Trip")
        let members = try names.map { try store.addMember(named: $0, to: group) }
        return (group, members)
    }

    // MARK: - Matching

    @Test("A member carrying this device's record name is me")
    func linkedMemberIsMe() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)

        try Self.withIdentity("_abc123") {
            members[1].cloudUserRecordName = "_abc123"

            #expect(CloudIdentity.isMe(members[1]))
            #expect(!CloudIdentity.isMe(members[0]))
            #expect(ExpenseDefaults.me(in: group, among: members) == members[1])
        }
    }

    /// The whole point of syncing the link: a second device of the same person
    /// resolves identity with nothing to tap, because it never wrote the local
    /// key in the first place.
    @Test("The link resolves identity with no local key set")
    func linkResolvesWithoutLocalKey() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)
        ExpenseDefaults.rememberMe(nil, in: group)

        try Self.withIdentity("_abc123") {
            members[0].cloudUserRecordName = "_abc123"
            #expect(ExpenseDefaults.me(in: group, among: members) == members[0])
        }
    }

    @Test("A member linked to another account is not me")
    func otherAccountIsNotMe() throws {
        let context = TestStack.makeContext()
        let (_, members) = try Self.makeGroup(members: ["Ala"], in: context)

        try Self.withIdentity("_mine") {
            members[0].cloudUserRecordName = "_theirs"

            #expect(!CloudIdentity.isMe(members[0]))
            #expect(CloudIdentity.isSomeoneElse(members[0]))
        }
    }

    @Test("An unlinked member belongs to nobody in particular")
    func unlinkedMemberIsNeutral() throws {
        let context = TestStack.makeContext()
        let (_, members) = try Self.makeGroup(members: ["Ala"], in: context)

        try Self.withIdentity("_mine") {
            #expect(!CloudIdentity.isMe(members[0]))
            #expect(!CloudIdentity.isSomeoneElse(members[0]))
        }
    }

    /// Signed out, nothing resolves — and in particular nothing *falsely*
    /// resolves. A `nil` account must not match a `nil` link.
    @Test("With no account signed in, no link matches")
    func signedOutMatchesNothing() throws {
        let context = TestStack.makeContext()
        let (_, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)

        try Self.withIdentity(nil) {
            members[0].cloudUserRecordName = "_abc123"

            #expect(!CloudIdentity.isMe(members[0]))
            #expect(!CloudIdentity.isMe(members[1]))
            // Unclaimed *and* signed out is still not "somebody else".
            #expect(!CloudIdentity.isSomeoneElse(members[1]))
        }
    }

    // MARK: - Precedence

    /// The disagreement that matters. This device once said "I am Ala", then Ala
    /// was claimed by a different Apple ID — someone corrected the roster, or two
    /// people picked the same name. The stale local key would badge their row
    /// "You", so it is dropped rather than honoured.
    @Test("A stale local identity loses to somebody else's claim")
    func staleLocalIdentityYieldsToClaim() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)
        ExpenseDefaults.rememberMe(members[0], in: group)

        try Self.withIdentity("_mine") {
            #expect(ExpenseDefaults.me(in: group, among: members) == members[0])

            members[0].cloudUserRecordName = "_theirs"
            #expect(ExpenseDefaults.me(in: group, among: members) == nil)
        }
    }

    @Test("The link wins when it and the local key name different members")
    func linkBeatsLocalKey() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)
        ExpenseDefaults.rememberMe(members[0], in: group)

        try Self.withIdentity("_mine") {
            members[1].cloudUserRecordName = "_mine"
            #expect(ExpenseDefaults.me(in: group, among: members) == members[1])
        }
    }

    /// A group that was never shared has no links at all, and has to keep
    /// working exactly as it did before any of this existed.
    @Test("An unshared group still resolves from the local key")
    func unsharedGroupUsesLocalKey() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)
        ExpenseDefaults.rememberMe(members[1], in: group)

        try Self.withIdentity("_mine") {
            #expect(ExpenseDefaults.me(in: group, among: members) == members[1])
        }
    }

    // MARK: - Claiming

    @Test("Claiming a member records this device's account on them")
    func claimWritesTheLink() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)

        try Self.withIdentity("_mine") {
            try GroupStore(context: context).claim(members[0], in: group)
            #expect(members[0].cloudUserRecordName == "_mine")
        }
    }

    /// Correcting a mistaken claim has to *move* the link. Left on both rows the
    /// same Apple ID would be two members, and `me` would return whichever the
    /// roster happened to sort first.
    @Test("Claiming a second member releases the first")
    func claimMovesRatherThanDuplicates() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)
        let store = GroupStore(context: context)

        try Self.withIdentity("_mine") {
            try store.claim(members[0], in: group)
            try store.claim(members[1], in: group)

            #expect(members[0].cloudUserRecordName == nil)
            #expect(members[1].cloudUserRecordName == "_mine")
            #expect(ExpenseDefaults.me(in: group, among: members) == members[1])
        }
    }

    @Test("Claiming nobody releases the link entirely")
    func claimingNilReleases() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala"], in: context)
        let store = GroupStore(context: context)

        try Self.withIdentity("_mine") {
            try store.claim(members[0], in: group)
            try store.claim(nil, in: group)

            #expect(members[0].cloudUserRecordName == nil)
        }
    }

    /// Claiming never touches anybody else's link — that is the difference
    /// between each person claiming their own row and the owner assigning them.
    @Test("Claiming leaves other accounts' links alone")
    func claimLeavesOtherAccountsAlone() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala", "Bartek"], in: context)
        members[1].cloudUserRecordName = "_theirs"

        try Self.withIdentity("_mine") {
            try GroupStore(context: context).claim(members[0], in: group)

            #expect(members[0].cloudUserRecordName == "_mine")
            #expect(members[1].cloudUserRecordName == "_theirs")
        }
    }

    /// Signed out, there is nothing to write. It must be a no-op rather than
    /// clearing whatever was already there.
    @Test("Claiming while signed out changes nothing")
    func claimSignedOutIsANoOp() throws {
        let context = TestStack.makeContext()
        let (group, members) = try Self.makeGroup(members: ["Ala"], in: context)
        members[0].cloudUserRecordName = "_theirs"

        try Self.withIdentity(nil) {
            try GroupStore(context: context).claim(members[0], in: group)
            #expect(members[0].cloudUserRecordName == "_theirs")
        }
    }
}

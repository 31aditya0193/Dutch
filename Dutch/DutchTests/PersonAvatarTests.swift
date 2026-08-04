/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

import CoreData
import Testing
@testable import Dutch

/// Covers the two things a derived avatar has to get right: it must hold still,
/// and within one group it must tell people apart. Neither is visible in a
/// screenshot — a colour that drifts between launches or between two phones
/// looking at the same shared group looks fine every single time you check it.
@MainActor
@Suite("Person avatars")
struct PersonAvatarTests {

    @discardableResult
    private static func makePerson(
        _ name: String?,
        id: UUID = UUID(),
        in context: NSManagedObjectContext
    ) -> Person {
        let person = Person(context: context)
        person.id = id
        person.name = name
        return person
    }

    // MARK: - Initials

    @Test("A full name abbreviates to two initials")
    func fullNameGivesTwoInitials() {
        #expect(PersonAvatar.initials(from: "Anna Kowalska") == "AK")
    }

    @Test("A single name gives one initial")
    func singleNameGivesOneInitial() {
        #expect(PersonAvatar.initials(from: "Anna") == "A")
    }

    /// The circle is 30pt wide. Three initials render as a smudge, and a name
    /// with a middle name is the ordinary way to get three.
    @Test("Initials never exceed two characters")
    func initialsAreCapped() throws {
        let initials = try #require(PersonAvatar.initials(from: "Johann Sebastian Bach"))
        #expect(initials.count <= 2)
    }

    @Test("A name that is only whitespace has no initials", arguments: ["", "   ", "\n"])
    func blankNamesHaveNoInitials(name: String) {
        #expect(PersonAvatar.initials(from: name) == nil)
    }

    @Test("A missing name has no initials")
    func missingNameHasNoInitials() {
        #expect(PersonAvatar.initials(from: nil) == nil)
    }

    /// The fallback path, for names the formatter declines to parse. It must
    /// still produce something — an empty circle in a list of coloured ones
    /// reads as a rendering bug.
    @Test("An unparseable name still yields a character", arguments: ["🎉", "#1", "أحمد"])
    func unparseableNamesStillYieldSomething(name: String) throws {
        let initials = try #require(PersonAvatar.initials(from: name))
        #expect(!initials.isEmpty)
    }

    // MARK: - Colour derivation

    /// The regression this guards is `hashValue`: Swift seeds its hasher per
    /// process, so a hash-derived colour would be stable within one launch and
    /// change on the next — which is exactly what comparing two calls in a row
    /// would not catch. Fixed bytes, fixed answer.
    @Test("Derivation reads the id's bytes, not a per-process hash")
    func derivationIsSeedIndependent() throws {
        let id = try #require(UUID(uuidString: "6E9F2C1A-4B3D-4E5F-8A7B-0C1D2E3F4A5B"))

        // 6E + 9F + 2C + 1A + 4B + 3D + 4E + 5F + 8A + 7B + 0C + 1D + 2E + 3F + 4A + 5B = 1224
        let expected = PaletteColor.allCases[1224 % PaletteColor.allCases.count]
        #expect(PaletteColor.derived(from: id) == expected)
    }

    @Test("A member with no id still gets a colour")
    func missingIdStillGetsAColour() {
        #expect(PaletteColor.derived(from: nil) == .blue)
    }

    // MARK: - Roster assignment

    @Test("No two members of a group share a colour")
    func rosterColoursAreDistinct() {
        let context = TestStack.makeContext()
        let members = (0..<PaletteColor.allCases.count).map { index in
            Self.makePerson("Member \(index)", in: context)
        }

        let avatars = RosterAvatars(members)
        let colors = members.map { avatars[$0].color }

        #expect(Set(colors).count == members.count)
    }

    /// 200 rosters, because a single draw of four ids can be distinct by luck —
    /// the collision this guards against happens well over half the time when
    /// each member picks independently.
    @Test("Colours stay distinct across many random rosters")
    func rosterColoursAreDistinctRepeatedly() {
        let context = TestStack.makeContext()

        for _ in 0..<200 {
            let members = (0..<4).map { Self.makePerson("Member \($0)", in: context) }
            let avatars = RosterAvatars(members)
            #expect(Set(members.map { avatars[$0].color }).count == 4)
        }
    }

    /// The reason the assignment walks an id-sorted roster rather than the
    /// name-sorted one the screens fetch: a rename must not repaint the group.
    @Test("Renaming a member leaves everyone's colour alone")
    func renamingDoesNotRepaintTheRoster() {
        let context = TestStack.makeContext()
        let members = (0..<5).map { Self.makePerson("Member \($0)", in: context) }

        let before = RosterAvatars(members)
        let original = members.map { before[$0].color }

        // Renamed to sort first, which is what would shuffle a name-ordered walk.
        members[3].name = "Aaron"

        let after = RosterAvatars(members)
        #expect(members.map { after[$0].color } == original)
    }

    /// Two devices hold the same group as two different `NSManagedObject`
    /// graphs, and the roster arrives in whatever order the store hands back.
    /// The colours have to come out the same anyway.
    @Test("Roster order does not change the assignment")
    func rosterOrderDoesNotMatter() {
        let context = TestStack.makeContext()
        let members = (0..<6).map { Self.makePerson("Member \($0)", in: context) }

        let forward = RosterAvatars(members)
        let backward = RosterAvatars(Array(members.reversed()))

        for member in members {
            #expect(forward[member].color == backward[member].color)
        }
    }

    /// Past eight the palette repeats rather than running out. What it must not
    /// do is hand everyone after the eighth the same colour.
    @Test("A roster larger than the palette cycles instead of collapsing")
    func oversizedRosterCycles() {
        let context = TestStack.makeContext()
        let size = PaletteColor.allCases.count + 3
        let members = (0..<size).map { Self.makePerson("Member \($0)", in: context) }

        let avatars = RosterAvatars(members)
        let counts = members.reduce(into: [PaletteColor: Int]()) { tally, member in
            tally[avatars[member].color, default: 0] += 1
        }

        // Eleven people over eight colours: three colours used twice, five once.
        #expect(counts.values.max() == 2)
        #expect(counts.count == PaletteColor.allCases.count)
    }

    // MARK: - Chosen colour

    @Test("A chosen colour is what the member gets")
    func chosenColourIsUsed() {
        let context = TestStack.makeContext()
        let member = Self.makePerson("Anna Kowalska", in: context)
        member.chosenColor = .pink

        #expect(RosterAvatars([member])[member].color == .pink)
    }

    /// The reason the assignment runs in two passes. In one pass whoever came
    /// first in the id-ordered walk would take a colour somebody else had
    /// explicitly asked for, and the person who chose it would watch their
    /// circle change because another member joined the group.
    @Test("A chosen colour displaces the automatic assignment, not the reverse")
    func chosenColourDisplacesTheDerivedOne() throws {
        let context = TestStack.makeContext()

        // A fixed id, so the colour the automatic member wants is known and the
        // collision this tests for is guaranteed rather than hoped for.
        let id = try #require(UUID(uuidString: "6E9F2C1A-4B3D-4E5F-8A7B-0C1D2E3F4A5B"))
        let contested = PaletteColor.derived(from: id)

        let automatic = Self.makePerson("Automatic", id: id, in: context)
        let chooser = Self.makePerson("Chooser", in: context)
        chooser.chosenColor = contested

        let avatars = RosterAvatars([automatic, chooser])
        #expect(avatars[chooser].color == contested)
        #expect(avatars[automatic].color != contested)
    }

    /// Unset has to stay a real state rather than a stored default that happens
    /// to match, or "Use Automatic Colour" would freeze today's answer forever.
    @Test("Clearing a chosen colour hands the member back to the derivation")
    func clearingRestoresTheDerivedColour() {
        let context = TestStack.makeContext()
        let member = Self.makePerson("Anna Kowalska", in: context)

        member.chosenColor = .pink
        member.chosenColor = nil

        #expect(member.colorName == nil)
        #expect(RosterAvatars([member])[member].color == .derived(from: member.id))
    }

    /// A newer version of the app can invent a colour and sync it down here. It
    /// must read as "nothing chosen" rather than crashing or drawing blank.
    @Test("A colour name this version doesn't know falls back to the derivation")
    func unknownColourNameFallsBack() {
        let context = TestStack.makeContext()
        let member = Self.makePerson("Anna Kowalska", in: context)
        member.colorName = "chartreuse"

        #expect(member.chosenColor == nil)
        #expect(RosterAvatars([member])[member].color == .derived(from: member.id))
    }

    /// A member the palette was not built from — a row that arrives mid-sync —
    /// must still draw, rather than falling through to nothing.
    @Test("A member outside the roster still gets an avatar")
    func strangerStillGetsAnAvatar() {
        let context = TestStack.makeContext()
        let known = Self.makePerson("Anna Kowalska", in: context)
        let stranger = Self.makePerson("Bruno Nowak", in: context)

        let avatars = RosterAvatars([known])
        #expect(avatars[stranger].color == .derived(from: stranger.id))
        #expect(avatars[stranger].initials == "BN")
    }
}

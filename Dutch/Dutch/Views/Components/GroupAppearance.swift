import CoreData
import SwiftUI

/// What a group looks like in a list: one symbol and one colour.
///
/// Purely decorative — nothing here is ever read to decide anything, and a group
/// with an appearance nobody recognises still splits money correctly. That is
/// what lets the stored values be plain strings that an older client can ignore.
struct GroupAppearance: Equatable {
    var symbol: GroupSymbol
    var color: GroupColor
}

// MARK: - Colour

/// The colours a group can be tinted.
///
/// Red and green are deliberately absent. The list row already spends both on
/// the one number that matters — red for what you owe, green for what you are
/// owed, see `Standing` — and a group tinted either would make that figure a
/// thing to double-check rather than read.
///
/// Stored by name rather than as a component triple, so restyling the palette
/// later restyles every group that already exists instead of freezing today's
/// RGB into everyone's database.
enum GroupColor: String, CaseIterable, Identifiable {
    case blue, teal, indigo, purple, pink, orange, brown, gray

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        case .brown: .brown
        case .gray: .gray
        }
    }

    /// Named for VoiceOver, which otherwise has nothing at all to say about a
    /// grid of coloured circles.
    var label: LocalizedStringKey {
        switch self {
        case .blue: "Blue"
        case .teal: "Teal"
        case .indigo: "Indigo"
        case .purple: "Purple"
        case .pink: "Pink"
        case .orange: "Orange"
        case .brown: "Brown"
        case .gray: "Grey"
        }
    }
}

// MARK: - Symbol

/// The symbols a group can carry.
///
/// A fixed set rather than the whole SF Symbols catalogue. Six thousand symbols
/// need a search field, a results grid and an empty state — a lot of screen for
/// a decoration — and availability varies by OS version, so a freeform name
/// could arrive from a newer device and render as nothing. Two dozen fit in one
/// grid with no scrolling to speak of, and every one of them exists on iOS 17.
///
/// Ordered by theme, because that is how someone scanning for "the ski trip one"
/// looks for it.
enum GroupSymbol: String, CaseIterable, Identifiable {
    // Getting there
    case airplane
    case car = "car.fill"
    case tram = "tram.fill"
    case ferry = "ferry.fill"
    case suitcase = "suitcase.fill"
    case map = "map.fill"

    // Outdoors
    case tent = "tent.fill"
    case beach = "beach.umbrella.fill"
    case mountains = "mountain.2.fill"
    case snow = "snowflake"
    case leaf = "leaf.fill"
    case paw = "pawprint.fill"

    // Home and everyday
    case house = "house.fill"
    case key = "key.fill"
    case cart = "cart.fill"
    case bag = "bag.fill"
    case bulb = "lightbulb.fill"
    case briefcase = "briefcase.fill"

    // Eating and going out
    case forkKnife = "fork.knife"
    case coffee = "cup.and.saucer.fill"
    case wine = "wineglass.fill"
    case cake = "birthday.cake.fill"
    case music = "music.note"
    case games = "gamecontroller.fill"

    var id: String { rawValue }

    /// The SF Symbol name — the raw value is the name, which is what keeps the
    /// stored string meaningful to anything reading the database directly.
    var systemName: String { rawValue }

    /// Spelled out for VoiceOver. Without it the picker is two dozen buttons
    /// announced as "fork.knife", read one dotted component at a time.
    var label: LocalizedStringKey {
        switch self {
        case .airplane: "Plane"
        case .car: "Car"
        case .tram: "Tram"
        case .ferry: "Ferry"
        case .suitcase: "Suitcase"
        case .map: "Map"
        case .tent: "Tent"
        case .beach: "Beach"
        case .mountains: "Mountains"
        case .snow: "Snow"
        case .leaf: "Leaf"
        case .paw: "Paw print"
        case .house: "House"
        case .key: "Key"
        case .cart: "Shopping cart"
        case .bag: "Bag"
        case .bulb: "Lightbulb"
        case .briefcase: "Briefcase"
        case .forkKnife: "Restaurant"
        case .coffee: "Coffee"
        case .wine: "Wine"
        case .cake: "Cake"
        case .music: "Music"
        case .games: "Games"
        }
    }
}

// MARK: - Derivation

extension GroupAppearance {
    /// The look a group falls back to when it has never been given one.
    ///
    /// Derived from the group's own id, so every group that existed before this
    /// feature did becomes distinct the moment the app updates — with no
    /// migration to write, nothing to sync, and no "pick an icon" chore standing
    /// between the user and a list they can already read.
    ///
    /// It has to be the *bytes* of the UUID, not `hashValue`: Swift seeds its
    /// hasher per process, so a hash-derived icon would change colour on every
    /// launch and differ between two phones looking at the same shared group.
    static func derived(from id: UUID?) -> GroupAppearance {
        guard let id else {
            // A record too incomplete to have an id is half-synced and about to
            // change anyway; anything stable will do.
            return GroupAppearance(symbol: .forkKnife, color: .blue)
        }

        // Two independent sums over alternating bytes, so the colour and the
        // symbol don't march in lockstep — folding one number would tie teal to
        // the same handful of glyphs forever.
        let (symbolSeed, colorSeed) = withUnsafeBytes(of: id.uuid) { bytes in
            bytes.enumerated().reduce(into: (UInt64(0), UInt64(0))) { seeds, byte in
                if byte.offset.isMultiple(of: 2) {
                    seeds.0 &+= UInt64(byte.element)
                } else {
                    seeds.1 &+= UInt64(byte.element)
                }
            }
        }

        return GroupAppearance(
            symbol: GroupSymbol.allCases[Int(symbolSeed % UInt64(GroupSymbol.allCases.count))],
            color: GroupColor.allCases[Int(colorSeed % UInt64(GroupColor.allCases.count))]
        )
    }

    /// A look for a group that doesn't exist yet, so the new-group sheet opens
    /// on something with a bit of personality and two groups made in a row don't
    /// arrive as twins.
    static var random: GroupAppearance {
        GroupAppearance(
            symbol: GroupSymbol.allCases.randomElement() ?? .forkKnife,
            color: GroupColor.allCases.randomElement() ?? .blue
        )
    }
}

// MARK: - Group

extension ExpenseGroup {
    /// How this group renders.
    ///
    /// The stored attributes are an override, not the source: an unset — or
    /// unrecognised — name falls back to the derived look rather than to a
    /// placeholder. Unrecognised matters, because a future version of the app
    /// may add a symbol this one has never heard of and sync it down here.
    var appearance: GroupAppearance {
        let derived = GroupAppearance.derived(from: id)
        return GroupAppearance(
            symbol: symbolName.flatMap(GroupSymbol.init(rawValue:)) ?? derived.symbol,
            color: colorName.flatMap(GroupColor.init(rawValue:)) ?? derived.color
        )
    }
}

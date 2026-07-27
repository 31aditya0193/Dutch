import Foundation

/// Generates human-readable word sequences such as `"coral-lotus-pearl"`.
///
/// These are **labels, not credentials**. Access to a group is granted only by
/// the CloudKit share the QR code carries; the word sequence exists so two
/// people can confirm out loud that they joined the same group. Don't add a
/// code path that treats a matching sequence as proof of membership.
public enum WordGenerator {
    public static let adjectives: [String] = [
        "amber", "aqua", "azure", "beige", "blush", "bronze", "cerulean",
        "coral", "crimson", "cyan", "emerald", "fuchsia", "gold", "indigo",
        "ivory", "jade", "lavender", "lilac", "lime", "magenta", "maroon",
        "mint", "navy", "olive", "orange", "peach", "periwinkle", "pink",
        "plum", "purple", "red", "rose", "ruby", "salmon", "sapphire",
        "scarlet", "silver", "tan", "teal", "turquoise", "violet",
        "white", "yellow",
    ]

    public static let nouns: [String] = [
        "apple", "avocado", "banana", "bear", "bird", "blueberry",
        "breeze", "cake", "candle", "cherry", "cloud", "cookie",
        "crystal", "daisy", "dawn", "dolphin", "dragon", "eagle",
        "echo", "falcon", "feather", "fire", "flower", "forest",
        "fox", "frog", "galaxy", "garden", "gem", "grape", "harbor",
        "honey", "horizon", "island", "jelly", "koala", "lantern",
        "lemon", "lily", "lotus", "maple", "meadow", "melon",
        "mist", "monkey", "moon", "mountain", "nova", "oak",
        "ocean", "olive", "opal", "orange", "orbit", "owl",
        "panda", "peach", "pearl", "pepper", "pine", "planet",
        "puma", "rain", "raven", "river", "robin", "robot",
        "rocket", "rose", "ruby", "salad", "sand", "sapphire",
        "snow", "solar", "spirit", "star", "stone", "storm",
        "sun", "sunset", "tiger", "toast", "topaz", "tulip",
        "turtle", "valley", "violet", "water", "whale", "winter",
        "wolf", "xenon", "yacht", "zebra", "zenith",
    ]

    /// The separator used for newly generated sequences.
    public static let separator = "-"

    /// Separators accepted when parsing, so sequences written by hand or by
    /// an older build still validate.
    static let recognisedSeparators: Set<Character> = ["-", ".", "~"]

    // MARK: - Generation

    /// Returns a sequence like `"coral-lotus-pearl"`: one adjective followed
    /// by nouns.
    /// - Parameter wordCount: Total number of words. Values below 2 are
    ///   raised to 2 so the result is always parseable.
    public static func generate(wordCount: Int = 3) -> String {
        let count = max(2, wordCount)
        var generator = SystemRandomNumberGenerator()
        return generate(wordCount: count, using: &generator)
    }

    /// Seedable variant, so tests can assert on exact output.
    public static func generate(
        wordCount: Int = 3,
        using generator: inout some RandomNumberGenerator
    ) -> String {
        let count = max(2, wordCount)
        let words = (0 ..< count).map { index -> String in
            let list = index == 0 ? adjectives : nouns
            return list.randomElement(using: &generator) ?? list[0]
        }
        return words.joined(separator: separator)
    }

    // MARK: - Validation

    /// Whether every word in `sequence` comes from the known dictionaries.
    ///
    /// A `true` result means the string is well-formed, nothing more — see the
    /// type-level note about these not being credentials.
    public static func isWellFormed(_ sequence: String) -> Bool {
        let words = split(sequence)
        guard words.count >= 2 else { return false }

        let vocabulary = Set(adjectives).union(nouns)
        return words.allSatisfy(vocabulary.contains)
    }

    static func split(_ sequence: String) -> [String] {
        sequence
            .lowercased()
            .split(whereSeparator: recognisedSeparators.contains)
            .map(String.init)
    }
}

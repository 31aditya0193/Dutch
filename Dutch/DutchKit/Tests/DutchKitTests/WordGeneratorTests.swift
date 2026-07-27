import Testing
@testable import DutchKit

@Suite("Word generator")
struct WordGeneratorTests {

    @Test("Generated sequences validate")
    func generatedSequencesAreWellFormed() {
        for _ in 0 ..< 200 {
            #expect(WordGenerator.isWellFormed(WordGenerator.generate()))
        }
    }

    @Test("The default sequence is three words")
    func defaultWordCount() {
        #expect(WordGenerator.split(WordGenerator.generate()).count == 3)
    }

    /// Regression: the generator used `$0` inside a closure that had already
    /// named its argument `_`, which did not compile. Once fixed, the first
    /// word must come from the adjective list and the rest from the nouns.
    @Test("The first word is an adjective and the rest are nouns")
    func wordRoles() {
        let adjectives = Set(WordGenerator.adjectives)
        let nouns = Set(WordGenerator.nouns)

        for _ in 0 ..< 200 {
            let words = WordGenerator.split(WordGenerator.generate(wordCount: 4))
            let restAreNouns = words.dropFirst().allSatisfy { nouns.contains($0) }
            #expect(words.count == 4)
            #expect(adjectives.contains(words[0]))
            #expect(restAreNouns)
        }
    }

    @Test("Word count never drops below two", arguments: [-5, 0, 1, 2])
    func wordCountFloor(requested: Int) {
        let words = WordGenerator.split(WordGenerator.generate(wordCount: requested))
        #expect(words.count >= 2)
    }

    @Test("Legacy separators still parse")
    func legacySeparators() {
        #expect(WordGenerator.isWellFormed("coral-lotus-pearl"))
        #expect(WordGenerator.isWellFormed("coral.lotus.pearl"))
        #expect(WordGenerator.isWellFormed("coral~lotus~pearl"))
        #expect(WordGenerator.isWellFormed("CORAL-LOTUS-PEARL"))
    }

    @Test("Unknown or malformed sequences are rejected")
    func rejectsJunk() {
        #expect(!WordGenerator.isWellFormed(""))
        #expect(!WordGenerator.isWellFormed("coral"))
        #expect(!WordGenerator.isWellFormed("coral-lotus-zzzz"))
        #expect(!WordGenerator.isWellFormed("https://www.icloud.com/share/abc"))
    }

    @Test("Generation is reproducible for a given seed")
    func seededGeneration() {
        var first = SeededGenerator(seed: 42)
        var second = SeededGenerator(seed: 42)
        #expect(
            WordGenerator.generate(using: &first) == WordGenerator.generate(using: &second)
        )
    }
}

/// Deterministic RNG so the seeded test asserts on real equality.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}

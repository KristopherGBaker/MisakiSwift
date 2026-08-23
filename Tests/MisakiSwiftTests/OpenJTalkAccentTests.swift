import Foundation
import Testing
@testable import MisakiJapanese
@testable import MisakiSwift

/// The dictionary lives outside the repo (it is downloaded on first use), so these
/// skip unless `OJT_DICT_DIR` points at an unpacked open_jtalk_dic_utf_8 directory.
private func dictionaryDirectory() -> URL? {
    guard let path = ProcessInfo.processInfo.environment["OJT_DICT_DIR"] else { return nil }
    let url = URL(fileURLWithPath: path)
    return FileManager.default.fileExists(atPath: url.appendingPathComponent("sys.dic").path) ? url : nil
}

@Suite("OpenJTalk accent — dictionary integration")
struct OpenJTalkAccentTests {

    /// NJD computes accent on every parse; this pins that `OpenJTalkWord` actually
    /// carries it out rather than dropping it at the public boundary, which is what
    /// it did before. Uses the textbook minimal triple: 箸 (はし) is atamadaka, 橋 is
    /// odaka, 端 is heiban, all with the same reading, so a word whose accent were
    /// hardcoded or zeroed could not pass.
    @Test("the はし minimal triple carries three distinct accent patterns")
    func accentMinimalTriple() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        func accent(of surface: String, in sentence: String) throws -> Int {
            let word = try #require(reader.words(for: sentence).first { $0.surface == surface })
            #expect(word.reading == "はし")
            #expect(word.moraCount == 2, "はし is two moras, so a nucleus above 2 would be impossible")
            return word.accent
        }

        let chopsticks = try accent(of: "箸", in: "箸を持つ")
        let bridge = try accent(of: "橋", in: "橋を渡る")
        let edge = try accent(of: "端", in: "端に置く")

        // Distinctness is the load-bearing assertion: it fails if accent is constant.
        #expect(Set([chopsticks, bridge, edge]).count == 3,
                "expected three distinct patterns, got 箸=\(chopsticks) 橋=\(bridge) 端=\(edge)")
        #expect(chopsticks == 1, "箸 is atamadaka")
        #expect(bridge == 2, "橋 is odaka")
        #expect(edge == 0, "端 is heiban")
    }

    /// Accent belongs to the phrase, not the word, so a consumer needs the chaining
    /// flag to group words. A particle attaches to the noun before it.
    @Test("accent-phrase chaining marks an attaching particle")
    func accentPhraseChaining() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        let words = reader.words(for: "箸を持つ")
        let particle = try #require(words.first { $0.surface == "を" })
        #expect(particle.attachesToPreviousWord,
                "を should attach to the preceding noun rather than open a phrase")
    }
}

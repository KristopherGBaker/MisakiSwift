import Foundation
import Testing
@testable import MisakiSwift

// MARK: - Pure logic (no dictionary, no MLX)

@Suite("OpenJTalk G2P — pure conversion")
struct OpenJTalkPureTests {

    @Test("katakana → hiragana by codepoint offset; non-katakana passes through")
    func katakanaToHiragana() {
        #expect(KanaToIPA.katakanaToHiragana("ハシ") == "はし")
        #expect(KanaToIPA.katakanaToHiragana("トーキョー") == "とーきょー")
        // NJD pron accent mark ’ and chōonpu pass through unchanged.
        #expect(KanaToIPA.katakanaToHiragana("ガク’セー") == "がく’せー")
    }

    @Test("katakana reading → in-vocab IPA via the shared KanaToIPA table")
    func pronToIPA() {
        let hira = KanaToIPA.katakanaToHiragana("ハシ")
        #expect(KanaToIPA.ipa(forHiragana: hira) == "haɕi")
        // ウ-series uses ɯ (Aoede vocab), not ASCII u.
        #expect(KanaToIPA.ipa(forHiragana: KanaToIPA.katakanaToHiragana("ク")) == "kɯ")
        // chōonpu → ː ; が → ɡa (U+0261, not ASCII g).
        #expect(KanaToIPA.ipa(forHiragana: KanaToIPA.katakanaToHiragana("トーキョー")) == "toːkʲoː")
    }

    @Test("pron2moras: greedy digraph grouping, drops non-mora marks")
    func pronToMoras() {
        #expect(OpenJTalkG2P.pronToMoras("ハシ") == ["ハ", "シ"])
        #expect(OpenJTalkG2P.pronToMoras("キョウ") == ["キョ", "ウ"])
        // ッ / ー / ン are their own moras; accent mark ’ is dropped.
        #expect(OpenJTalkG2P.pronToMoras("ガク’セー") == ["ガ", "ク", "セ", "ー"])
        #expect(OpenJTalkG2P.pronToMoras("ミッカ") == ["ミ", "ッ", "カ"])
    }
}

// MARK: - Integration against the real Open JTalk dictionary

/// Locate the UTF-8 dictionary for integration tests. Set `OJT_DICT_DIR` to the
/// directory containing `sys.dic` (e.g. the pyopenjtalk `open_jtalk_dic_utf_8-1.11`).
/// Tests skip when it is absent so the pure suite still runs everywhere.
private func dictionaryDirectory() -> URL? {
    guard let path = ProcessInfo.processInfo.environment["OJT_DICT_DIR"] else { return nil }
    let url = URL(fileURLWithPath: path)
    return FileManager.default.fileExists(atPath: url.appendingPathComponent("sys.dic").path) ? url : nil
}

@Suite("OpenJTalk G2P — dictionary integration")
struct OpenJTalkIntegrationTests {

    @Test("二三 idiom reads にさん / ニサン (not にじゅうさん / ニジュウサン) across all three surfaces")
    func nisanIdiom() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let g2p = try #require(OpenJTalkG2P(dictionaryDirectory: dir))
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // Furigana: OpenJTalkReader orthographic hiragana.
        #expect(reader.orthographicHiraganaReading(for: "二三") == "にさん")
        #expect(reader.orthographicHiraganaReading(for: "二三日") == "にさんにち")
        #expect(reader.orthographicHiraganaReading(for: "二三人") == "にさんにん")

        // Spoken katakana: OpenJTalkG2P.analyze().pron (NOT ニジュウサン).
        #expect(g2p.analyze("二三").map { $0.pron }.joined() == "ニサン")
        #expect(g2p.analyze("二三日").map { $0.pron }.joined() == "ニサンニチ")
        #expect(g2p.analyze("二三人").map { $0.pron }.joined() == "ニサンニン")

        // Spoken phonemes: 二三 == にさん != 二十三, with the pinned literal stream.
        #expect(g2p.phonemize(text: "二三").0 == "ɲisaɴ")
        #expect(g2p.phonemize(text: "二三").0 == g2p.phonemize(text: "にさん").0)
        #expect(g2p.phonemize(text: "二三").0 != g2p.phonemize(text: "二十三").0)
        #expect(g2p.phonemize(text: "二三日").0 == "ɲisaɴ ɲiʨi")
        #expect(g2p.phonemize(text: "二三人").0 == "ɲisaɴ ɲiɴ")
    }

    @Test("no-regression: genuine numbers unchanged vs unmodified baseline (literal-pinned)")
    func genuineNumbersUnchanged() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let g2p = try #require(OpenJTalkG2P(dictionaryDirectory: dir))
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // Literals captured from the UNMODIFIED baseline (frontend on HEAD before the fix):
        // (surface, hiragana, katakana pron, phoneme string).
        let cases: [(String, String, String, String)] = [
            ("二十三", "にじゅうさん", "ニジューサン", "ɲi ʥɨː saɴ"),
            ("二十三日", "にじゅうさんにち", "ニジューサンニチ", "ɲi ʥɨː saɴ ɲiʨi"),
            ("二千八百円", "にせんはちひゃくえん", "ニセンハッピャクエン", "ɲi seɴ haʔ pʲakɯeɴ"),
            ("二千四百円", "にせんよんひゃくえん", "ニセンヨンヒャクエン", "ɲi seɴ joɴ çakɯeɴ")
        ]
        for (surface, hira, pron, phon) in cases {
            #expect(reader.orthographicHiraganaReading(for: surface) == hira)
            #expect(g2p.analyze(surface).map { $0.pron }.joined() == pron)
            #expect(g2p.phonemize(text: surface).0 == phon)
        }
    }

    @Test("phonemic pitch: 箸 (acc=1) vs 橋 (acc=2) read identically but differ in accent")
    func pitchMinimalPair() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let g2p = try #require(OpenJTalkG2P(dictionaryDirectory: dir))

        let hashi1 = g2p.analyze("箸")
        let hashi2 = g2p.analyze("橋")
        #expect(hashi1.first?.pron == "ハシ")
        #expect(hashi2.first?.pron == "ハシ")
        #expect(hashi1.first?.acc == 1)
        #expect(hashi2.first?.acc == 2)
        // Same clean IPA by default (accent lives in metadata, not the stream).
        #expect(hashi1.first?.phonemes == "haɕi")
        #expect(hashi2.first?.phonemes == "haɕi")
    }

    @Test("readings fixed vs Phase 1: 私→ワタシ, contextual particle は→ワ, counters")
    func readingsFixed() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let g2p = try #require(OpenJTalkG2P(dictionaryDirectory: dir))

        let words = g2p.analyze("私は学生です")
        #expect(words.first(where: { $0.surface == "私" })?.pron == "ワタシ")
        #expect(words.first(where: { $0.surface == "は" })?.pron == "ワ")

        #expect(g2p.analyze("3日").first?.pron == "ミッカ")
        let yen = g2p.analyze("100円")
        #expect(yen.contains { $0.pron == "ヒャク" })
        #expect(yen.contains { $0.pron == "エン" })
    }

    @Test("hard contract: phonemeString == Σ(phonemes + whitespace), in order")
    func phonemeStringInvariant() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let g2p = try #require(OpenJTalkG2P(dictionaryDirectory: dir))

        for text in ["箸を持つ", "私は学生です", "東京。", "100円です"] {
            let (phonemeString, tokens) = g2p.phonemize(text: text)
            let rebuilt = tokens.map { ($0.phonemes ?? "") + $0.whitespace }.joined()
            #expect(phonemeString == rebuilt)
            // No empty-phoneme + empty-whitespace tokens (would stall the predictor).
            for token in tokens {
                #expect(!((token.phonemes ?? "").isEmpty && token.whitespace.isEmpty))
            }
        }
    }

    @Test("hard contract: every phoneme character is in the Kokoro vocab")
    func everyCharInVocab() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let g2p = try #require(OpenJTalkG2P(dictionaryDirectory: dir))
        // The whitespace + a small set of in-vocab punctuation are also allowed.
        let extra = Set(" .,!?:;()\u{201C}\u{201D}…—")
        for text in ["箸を持つ", "私は学生です", "東京", "100円", "3日", "こんにちは"] {
            let (phonemeString, _) = g2p.phonemize(text: text)
            for ch in phonemeString where !extra.contains(ch) {
                #expect(KokoroVocabFixture.contains(ch), "OOV char \(ch) in \(text)")
            }
        }
    }

    @Test("downstep flag injects ↓ only at the nucleus, and only when enabled")
    func downstepGated() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")

        let clean = try #require(OpenJTalkG2P(dictionaryDirectory: dir, injectDownstep: false))
        #expect(!clean.phonemize(text: "箸").0.contains("↓"))

        let marked = try #require(OpenJTalkG2P(dictionaryDirectory: dir, injectDownstep: true))
        // 箸 acc=1 → nucleus on mora 1 → a single ↓ in the stream.
        #expect(marked.phonemize(text: "箸").0.contains("↓"))
    }
}

import Foundation
import Testing
@testable import MisakiJapanese
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
        #expect(OpenJTalkKokoroG2P.pronToMoras("ハシ") == ["ハ", "シ"])
        #expect(OpenJTalkKokoroG2P.pronToMoras("キョウ") == ["キョ", "ウ"])
        // ッ / ー / ン are their own moras; accent mark ’ is dropped.
        #expect(OpenJTalkKokoroG2P.pronToMoras("ガク’セー") == ["ガ", "ク", "セ", "ー"])
        #expect(OpenJTalkKokoroG2P.pronToMoras("ミッカ") == ["ミ", "ッ", "カ"])
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
        let g2p = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir))
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
        let g2p = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir))
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
        let g2p = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir))

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
        let g2p = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir))

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
        let g2p = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir))

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
        let g2p = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir))
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

        let clean = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir, injectDownstep: false))
        #expect(!clean.phonemize(text: "箸").0.contains("↓"))

        let marked = try #require(OpenJTalkKokoroG2P(dictionaryDirectory: dir, injectDownstep: true))
        // 箸 acc=1 → nucleus on mora 1 → a single ↓ in the stream.
        #expect(marked.phonemize(text: "箸").0.contains("↓"))
    }
}

// MARK: - Reconciled furigana reading (dictionary integration)

@Suite("OpenJTalk reader — reconciled furigana reading")
struct FuriganaReadingTests {

    @Test("furiganaReading reconciles pron×read: sound-changes from pron, long vowels from read")
    func furiganaReconciled() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // Long vowels come from `read` (pron would give ほお / せんせえ / …):
        #expect(reader.furiganaReading(for: "方") == "ほう")
        #expect(reader.furiganaReading(for: "先生") == "せんせい")
        #expect(reader.furiganaReading(for: "東京") == "とうきょう")
        // Sound-change comes from `pron` (read would give はちひゃく):
        #expect(reader.furiganaReading(for: "八百") == "はっぴゃく")
        // Gemination + long vowel together:
        #expect(reader.furiganaReading(for: "学校") == "がっこう")
        // Genuine double vowels preserved:
        #expect(reader.furiganaReading(for: "大きい") == "おおきい")
        #expect(reader.furiganaReading(for: "通り") == "とおり")
        // Accent-nucleus marker (’ U+2019) in pron must not leak into furigana, and must not
        // inflate the mora count (which would strand a spoken long vowel): pron gives けっし’て /
        // ごち’そお / ち’そお, but furigana is the clean, orthographic reading.
        #expect(reader.furiganaReading(for: "決して") == "けっして")
        #expect(reader.furiganaReading(for: "ご馳走") == "ごちそう")
        #expect(reader.furiganaReading(for: "馳走") == "ちそう")
        // And the accent marker never survives in the output at all:
        #expect(reader.furiganaReading(for: "決して")?.contains("\u{2019}") == false)
    }

    @Test("furiganaReading preserves nil-semantics — matches the pron accessor on the same input")
    func furiganaNilSemantics() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // Returns `nil` exactly when the frontend yields no reading — the same nil-semantics as
        // the existing accessors. (In this dictionary build punctuation-only "。" is normalised to
        // 、 by the NJD frontend rather than dropped, so both accessors and furigana return "、";
        // the empty string is the genuine no-reading case.)
        #expect(reader.furiganaReading(for: "。") == reader.hiraganaReading(for: "。"))
        #expect(reader.furiganaReading(for: "") == nil)
        #expect(reader.hiraganaReading(for: "") == nil)
    }

    @Test("baseline pins: current pron (hiraganaReading) + read (orthographicHiraganaReading)")
    func baselinePins() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // (surface, pron == hiraganaReading, read == orthographicHiraganaReading) captured from
        // the CURRENT frontend — the reconcile is grounded in these observed inputs.
        let cases: [(String, String, String)] = [
            ("方", "ほお", "ほう"),
            ("八百", "はっぴゃく", "はちひゃく"),
            ("先生", "せんせえ", "せんせい"),
            ("大きい", "おおきい", "おおきい"),
            ("通り", "とおり", "とおり"),
            ("学校", "がっこお", "がっこう"),
            ("東京", "とおきょお", "とうきょう")
        ]
        for (surface, pron, read) in cases {
            #expect(reader.hiraganaReading(for: surface) == pron)
            #expect(reader.orthographicHiraganaReading(for: surface) == read)
        }
    }

    @Test("existing accessors unchanged: 方 → pron ほお / read ほう (the reconcile's two inputs)")
    func accessorsUnchanged() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))
        #expect(reader.hiraganaReading(for: "方") == "ほお")
        #expect(reader.orthographicHiraganaReading(for: "方") == "ほう")
    }

    @Test("furiganaWords segments by OpenJTalk boundaries with reconciled readings")
    func furiganaWordsSegmentation() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        func reading(_ line: String, surface: String) -> String? {
            reader.furiganaWords(for: line).first { $0.surface == surface }?.reading
        }
        // 一つ stays ONE word reading ひとつ (the external tokenizer would split 一 → いち):
        #expect(reading("壺が一つ", surface: "一つ") == "ひとつ")
        // Reconcile quality is preserved at the word level (八百 → はっぴゃく, not はちひゃく):
        #expect(reader.furiganaWords(for: "八百").map(\.reading).joined() == "はっぴゃく")
        // 撫でる is one word なでる (so 撫 won't absorb its okurigana into なで):
        #expect(reader.furiganaWords(for: "彼を撫でる").contains { $0.surface == "撫でる" && $0.reading == "なでる" })
        // Surfaces tile the line (punctuation carried through with an empty reading):
        let joined = reader.furiganaWords(for: "壺が一つ").map(\.surface).joined()
        #expect(joined == "壺が一つ")
    }

    @Test("orthographic-kana broadening: づ survives (not ず), は survives a contracted わ")
    func orthographicKanaThroughFurigana() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // Measured pre-fix: pron=ち’かずく / read=ちかづく, reconciled (buggy) → ちかずく.
        // Fixed reconciliation must spell the yotsugana づ, matching `read`.
        let chikazuku = try #require(reader.furiganaReading(for: "近づく"))
        #expect(chikazuku == "ちかづく")
        #expect(chikazuku.contains("かづ"))
        #expect(!chikazuku.contains("かず"))

        let kizuku = try #require(reader.furiganaReading(for: "気づく"))
        #expect(kizuku == "きづく")
        #expect(kizuku.contains("きづ"))
        #expect(!kizuku.contains("きず"))

        let tsuzukeru = try #require(reader.furiganaReading(for: "続ける"))
        #expect(tsuzukeru == "つづける")
        #expect(tsuzukeru.contains("つづ"))
        #expect(!tsuzukeru.contains("つず"))

        // 今晩は: contracted topic-marker は, spoken わ. Fixed reconciliation spells は.
        let konbanwa = try #require(reader.furiganaReading(for: "今晩は"))
        #expect(konbanwa == "こんばんは")
        #expect(konbanwa.contains("んは"))
        #expect(!konbanwa.contains("んわ"))
    }

    @Test("split volitional via furiganaWords: 行こう reads う, never a bare ー")
    func volitionalNoChoonpu() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // furiganaWords is the per-word path where OpenJTalk splits 行こう into 行こ + う and
        // the auxiliary's own `pron` is a bare chōonpu with nothing before it to attach to —
        // this is where the pre-fix defect actually lived (furiganaReading on the whole string
        // already reconciled fine, because it concatenates pron/read before reconciling).
        let words = reader.furiganaWords(for: "行こう")
        let joined = words.map(\.reading).joined()
        #expect(joined == "いこう")
        #expect(joined.contains("う"))
        #expect(!joined.contains("ー"))
    }

    @Test("regression guard: no furiganaWords reading contains a bare chōonpu")
    func noChoonpuLeaksIntoFurigana() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // A spread of hiragana-only-expected inputs: long-vowel nouns, the volitional auxiliary,
        // and a plain sentence. None of their reconciled readings may contain ー.
        let lines = ["行こう", "言おう", "続けよう", "方", "先生", "東京", "私は学生です"]
        for line in lines {
            for word in reader.furiganaWords(for: line) {
                #expect(!word.reading.contains("ー"), "ー leaked into furigana for \(word.surface) in \"\(line)\"")
            }
        }
    }

    @Test("synthesis path (pron) is untouched by the furigana fix — hiraganaReading pins")
    func synthesisPathUnchanged() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // Conductor-measured pre-fix pron values, pinned exactly. `hiraganaReading` reads the
        // `pron` keypath directly (this unit never touches it) and is expected to still carry
        // the phonetic spelling — including the accent-nucleus marker ’ (U+2019) on 近づく,
        // which a pin of "ちかずく" would silently fail to catch.
        let cases: [(String, String)] = [
            ("近づく", "ち\u{2019}かずく"),
            ("気づく", "きずく"),
            ("続ける", "つずける"),
            ("今晩は", "こんばんわ"),
            ("基づく", "もとずく"),
            ("相づち", "あいずち")
        ]
        for (surface, pron) in cases {
            #expect(reader.hiraganaReading(for: surface) == pron)
        }
    }

    @Test("both paths agree on 続: isolated-surface and in-line furiganaWords both spell づ")
    func bothPathsAgreeOnTsuzuku() throws {
        let dir = try #require(dictionaryDirectory(), "set OJT_DICT_DIR to run")
        let reader = try #require(OpenJTalkReader(dictionaryDirectory: dir))

        // The two extraction paths do NOT have to agree, and asserting that they do was
        // wrong. Measured: `furiganaReading("続い")` on the bare surface gives そくい, because
        // an isolated re-analysis reads 続 as the standalone そく; the same surface inside a
        // sentence is analysed as ツズイ/ツヅイ. That is the same isolated-versus-in-context
        // divergence that makes 静か re-tokenize to しずかか on its own, and it is upstream of
        // anything this fix touches.
        //
        // What the fix owes is narrower and is what is asserted here: WHEREVER the reader
        // produces a reading for this surface, the yotsugana is spelled づ and never ず.
        func inLineReading(_ line: String, surface: String) -> String? {
            reader.furiganaWords(for: line).first { $0.surface == surface }?.reading
        }

        // In context, which is the path the reader renders from.
        let inLineI = try #require(inLineReading("雨が続いた", surface: "続い"))
        #expect(inLineI.contains("づ"))
        #expect(!inLineI.contains("ず"))
        // And the isolated path is a different word, recorded so nobody re-asserts equality.
        #expect(reader.furiganaReading(for: "続い") == "そくい")

        let isolatedKe = try #require(reader.furiganaReading(for: "続け"))
        let inLineKe = try #require(inLineReading("作業を続けた", surface: "続け"))
        #expect(isolatedKe == inLineKe)
        #expect(isolatedKe.contains("づ"))
        #expect(!isolatedKe.contains("ず"))
    }
}

// MARK: - Reconcile helper (pure, no dictionary)

@Suite("OpenJTalk reader — furigana reconcile (pure)")
struct FuriganaReconcilePureTests {

    @Test("long-vowel swap: pron's spoken お / え lengthener → read's orthographic う / い")
    func longVowelSwap() {
        #expect(OpenJTalkReader.reconcileFurigana(pron: "ほお", read: "ほう") == "ほう")
        #expect(OpenJTalkReader.reconcileFurigana(pron: "せんせえ", read: "せんせい") == "せんせい")
        #expect(OpenJTalkReader.reconcileFurigana(pron: "とおきょお", read: "とうきょう") == "とうきょう")
    }

    @Test("sound-change (八百-like): pron is the base, read's spelling is discarded")
    func soundChange() {
        // Moras align 4:4 but differ by consonant/gemination, not a long-vowel lengthener,
        // so `pron` wins at every mora.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "はっぴゃく", read: "はちひゃく") == "はっぴゃく")
    }

    @Test("genuine double vowels pass through unchanged")
    func genuineDoubleVowels() {
        #expect(OpenJTalkReader.reconcileFurigana(pron: "おおきい", read: "おおきい") == "おおきい")
        #expect(OpenJTalkReader.reconcileFurigana(pron: "とおり", read: "とおり") == "とおり")
    }

    @Test("mora-count mismatch → pron returned unchanged (audio-truth fallback)")
    func moraMismatchFallback() {
        // Differing gemination ⇒ unequal mora count after small-kana normalisation ⇒ keep pron.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "がっこう", read: "がこう") == "がっこう")
    }

    @Test("yotsugana: pron's ず/じ → read's etymological づ/ぢ")
    func yotsugana() {
        // 近づい (measured): pron チカズイ / read チカヅイ → づ wins.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "ちかずい", read: "ちかづい") == "ちかづい")
        // 近づく (measured): pron チカズク / read チカヅク → づ wins.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "ちかずく", read: "ちかづく") == "ちかづく")
        // 気づく (measured): pron キズク / read キヅク → づ wins.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "きずく", read: "きづく") == "きづく")
        // じ/ぢ mirrors ず/づ (same yotsugana merger, opposite consonant voicing source):
        // 鼻血 pron ハナジ / read ハナヂ → ぢ wins.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "はなじ", read: "はなぢ") == "はなぢ")
    }

    @Test("bare chōonpu mora: pron's detached ー → read's spelled-out vowel, unconditioned")
    func detachedChoonpu() {
        // The split volitional (行こ + う): the auxiliary's pron is a lone ー with nothing
        // before it in THIS aligned pair to carry a previous-vowel condition — read always wins.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "いこー", read: "いこう") == "いこう")
        // Against a different read vowel column (い, not う) — proves the rule is "ー vs any
        // kana", not just a rename of the お/う case:
        #expect(OpenJTalkReader.reconcileFurigana(pron: "せんせー", read: "せんせい") == "せんせい")
    }

    @Test("contracted particles: pron's spoken わ/え/お → read's written は/へ/を")
    func contractedParticles() {
        // 今晩は (measured): pron コンバンワ / read コンバンハ → は wins.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "こんばんわ", read: "こんばんは") == "こんばんは")
        // へ as a directional particle is spoken え:
        #expect(OpenJTalkReader.reconcileFurigana(pron: "わたしえ", read: "わたしへ") == "わたしへ")
        // を is spoken お:
        #expect(OpenJTalkReader.reconcileFurigana(pron: "みずお", read: "みずを") == "みずを")
    }

    @Test("broadened rule does not eat genuine sound-changes or already-correct reconciliations")
    func soundChangesStillPreserved() {
        // 八百: gemination, not an alternation pair — pron wins (covered by soundChange() above
        // too; re-asserted here alongside its siblings so a regression in any one is isolated).
        #expect(OpenJTalkReader.reconcileFurigana(pron: "はっぴゃく", read: "はちひゃく") == "はっぴゃく")
        // 決して: pron carries the accent marker (けっし’て) but pron/read agree once stripped —
        // no alternation fires, marker-stripping alone produces the answer.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "けっし’て", read: "けっして") == "けっして")
        // ご馳走 / 馳走: accent marker + the pre-existing お/う long-vowel case, still both correct
        // under the broadened predicate (its case list is additive, not a replacement).
        #expect(OpenJTalkReader.reconcileFurigana(pron: "ごち’そお", read: "ごちそう") == "ごちそう")
        #expect(OpenJTalkReader.reconcileFurigana(pron: "ち’そお", read: "ちそう") == "ちそう")
        // 東京: the pre-existing お-column long-vowel case, unaffected by the new pairs.
        #expect(OpenJTalkReader.reconcileFurigana(pron: "とおきょお", read: "とうきょう") == "とうきょう")
    }
}

//
//  MisakiSwift — OpenJTalk reading lookup (for furigana)
//
//  A small public surface over the OpenJTalk frontend that returns a token's
//  kana reading (hiragana), so a UI layer can show furigana that matches the
//  spoken OpenJTalk reading (私→わたし, contextual particles) rather than the
//  system tokenizer's first-reading guess. Independent of the G2P phoneme path;
//  it reuses the same dictionary. Available only when the dictionary is present.
//

import Foundation

/// One analyzed word from the OpenJTalk frontend: its surface form, dictionary base form
/// (for JMDict-style lookup), and orthographic hiragana reading. Reading is empty when the
/// word has no reading (e.g. punctuation); `baseForm` falls back to `surface` for words with
/// no morphological base (numbers, punctuation, names).
public struct OpenJTalkWord: Sendable, Hashable {
    public let surface: String
    public let baseForm: String
    public let reading: String

    /// Accent nucleus as a 1-based mora index, or 0 for heiban (no downstep).
    /// This is NJD's `acc`, produced by `njd_set_accent_type` during analysis.
    /// A value of 2 on a 3-mora word means the pitch falls after its second mora.
    public let accent: Int

    /// Number of moras in the reading. Pairs with `accent`, which is meaningless
    /// without it: a nucleus of 3 is final-accented on a 3-mora word and
    /// impossible on a 2-mora one.
    public let moraCount: Int

    /// How this word joins the previous one into an accent phrase, from NJD's
    /// `chain_flag`: -1 begins a phrase, 1 attaches to the preceding word, 0
    /// starts a new one. Accent is a property of the phrase rather than the
    /// word, so a consumer rendering pitch needs this to group words correctly.
    public let accentPhraseChain: Int

    /// Whether this word attaches to the preceding one rather than beginning a
    /// new accent phrase.
    public var attachesToPreviousWord: Bool { accentPhraseChain == 1 }

    public init(
        surface: String,
        baseForm: String,
        reading: String,
        accent: Int = 0,
        moraCount: Int = 0,
        accentPhraseChain: Int = 0
    ) {
        self.surface = surface
        self.baseForm = baseForm
        self.reading = reading
        self.accent = accent
        self.moraCount = moraCount
        self.accentPhraseChain = accentPhraseChain
    }
}

/// Furigana-oriented reading lookup backed by the OpenJTalk frontend. Holds one
/// dictionary load and serializes calls internally (the frontend mutates per-call
/// C state), so it's safe to share across threads.
public final class OpenJTalkReader: @unchecked Sendable {
    private let frontend: OJTFrontend
    private let lock = NSLock()

    /// Load the UTF-8 Open JTalk dictionary at `dictionaryDirectory`; `nil` if it
    /// can't be loaded.
    public init?(dictionaryDirectory: URL) {
        guard let frontend = OJTFrontend(dictionaryDirectory: dictionaryDirectory) else { return nil }
        self.frontend = frontend
    }

    /// A reader for the globally configured dictionary, or `nil` if none is set
    /// (i.e. the dictionary hasn't been downloaded yet — caller falls back).
    public static func makeFromConfiguredDictionary() -> OpenJTalkReader? {
        guard let directory = JapaneseG2PConfiguration.dictionaryDirectory else { return nil }
        return OpenJTalkReader(dictionaryDirectory: directory)
    }

    /// Hiragana reading for a token — its OpenJTalk pron (katakana) converted to
    /// hiragana. `nil` when the frontend yields no reading (e.g. punctuation).
    ///
    /// This is the *phonetic* reading: long vowels are spoken (今日→きょお, 先生→せんせえ).
    /// For orthographic furigana (きょう/せんせい) use `orthographicHiraganaReading(for:)`.
    public func hiraganaReading(for text: String) -> String? {
        reading(for: text, keyPath: \.pron)
    }

    /// Orthographic hiragana reading for a token — its OpenJTalk `read` (katakana) converted
    /// to hiragana. Long vowels follow standard spelling (今日→きょう, 先生→せんせい), which is
    /// what furigana conventionally shows. `nil` when the frontend yields no reading.
    public func orthographicHiraganaReading(for text: String) -> String? {
        reading(for: text, keyPath: \.read)
    }

    /// Reconciled hiragana furigana reading for `text` — correct on **both** sound-changes and
    /// long-vowel spelling. It combines the two existing readings mora-by-mora:
    ///
    /// - **pron** (`hiraganaReading`) is the base: it has the right sound-changes (八百→はっぴゃく,
    ///   not はちひゃく) but spells long vowels phonetically (方→ほお, 先生→せんせえ).
    /// - **read** (`orthographicHiraganaReading`) has the right orthographic long vowels (方→ほう,
    ///   先生→せんせい) but the wrong sound-changes (八百→はちひゃく).
    ///
    /// The pron×read rule (see `reconcileFurigana(pron:read:)`): keep `pron` everywhere, except
    /// where an aligned mora differs *only* by a long-vowel lengthener — `pron` shows the spoken
    /// vowel (お-column …お / え-column …え) while `read` shows the orthographic one (…う / …い) —
    /// there the mora from `read` is taken. Genuine double vowels (both agree) pass through.
    ///
    /// Preserves the existing multi-word concatenation and nil-semantics: returns `nil` exactly
    /// when the frontend yields no reading (same as `hiraganaReading` on the same input).
    public func furiganaReading(for text: String) -> String? {
        // nil-semantics follow the pron accessor (`hiraganaReading`): nil iff no reading.
        guard let pron = reading(for: text, keyPath: \.pron) else { return nil }
        // If `read` is somehow absent, fall back to the audio-truth rather than dropping the word
        // (still stripped of the accent marker so it never leaks into the furigana).
        guard let read = reading(for: text, keyPath: \.read) else { return Self.stripAccentMarks(pron) }
        return Self.reconcileFurigana(pron: pron, read: read)
    }

    /// Tokenize a Japanese line via OpenJTalk's own morphological boundaries and return each
    /// word's surface form plus its orthographic hiragana reading. Analyzing the *whole* line
    /// is what lets context-sensitive readings come out right — e.g. `7年` is seen together so
    /// 年 reads as the counter ねん (rather than the standalone noun とし the system tokenizer
    /// would produce if 年 were handed over in isolation). Pass one line at a time (no
    /// newlines); empty input returns `[]`.
    public func words(for line: String) -> [OpenJTalkWord] {
        lock.lock()
        defer { lock.unlock() }
        return frontend.runFrontend(line).map { word in
            // NJD's `orig` is missing for entries with no morphological base — fall back to
            // the surface so callers always have *something* to look up.
            let base = word.base.isEmpty ? word.surface : word.base
            let katakana = word.read
            guard !katakana.isEmpty else {
                return OpenJTalkWord(
                    surface: word.surface, baseForm: base, reading: "",
                    accent: word.acc, moraCount: word.moraSize, accentPhraseChain: word.chainFlag)
            }
            let mutable = NSMutableString(string: katakana)
            CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)
            return OpenJTalkWord(
                surface: word.surface, baseForm: base, reading: mutable as String,
                accent: word.acc, moraCount: word.moraSize, accentPhraseChain: word.chainFlag)
        }
    }

    /// Tokenize a line via OpenJTalk's morphological boundaries and return each word's surface,
    /// dictionary base form, and **reconciled** furigana reading (pron×read — correct on *both*
    /// sound-changes and long-vowel spelling, exactly like `furiganaReading(for:)` but per word).
    /// One frontend pass, so cross-word context (counters, sound-changes) is preserved.
    ///
    /// This is the word-level analog of `furiganaReading(for:)`: use it to segment furigana by
    /// OpenJTalk's own word boundaries rather than by an external tokenizer that would split e.g.
    /// 一つ into 一 + つ (→ いち instead of ひと) or make 撫 absorb its okurigana. Words with no
    /// reading (punctuation) come back with `reading == ""` so the surfaces still tile the line.
    /// Pass one line at a time (no newlines); empty input returns `[]`.
    public func furiganaWords(for line: String) -> [OpenJTalkWord] {
        lock.lock()
        defer { lock.unlock() }
        return frontend.runFrontend(line).map { word in
            let base = word.base.isEmpty ? word.surface : word.base
            let reading = Self.reconciledReading(pronKatakana: word.pron, readKatakana: word.read)
            return OpenJTalkWord(
                surface: word.surface, baseForm: base, reading: reading,
                accent: word.acc, moraCount: word.moraSize, accentPhraseChain: word.chainFlag)
        }
    }

    /// The reconciled hiragana reading from a single frontend word's katakana `pron` + `read`.
    /// Mirrors `furiganaReading(for:)` at the word granularity (pron base, read's long vowels,
    /// pron fallback when `read` is absent).
    private static func reconciledReading(pronKatakana: String, readKatakana: String) -> String {
        let pron = hiragana(fromKatakana: pronKatakana)
        guard !pron.isEmpty else { return "" }
        let read = hiragana(fromKatakana: readKatakana)
        guard !read.isEmpty else { return stripAccentMarks(pron) }
        return reconcileFurigana(pron: pron, read: read)
    }

    private static func hiragana(fromKatakana katakana: String) -> String {
        guard !katakana.isEmpty else { return "" }
        let mutable = NSMutableString(string: katakana)
        CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)   // katakana → hiragana
        return mutable as String
    }

    private func reading(for text: String, keyPath: KeyPath<OJTWord, String>) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let katakana = frontend.runFrontend(text).map { $0[keyPath: keyPath] }.joined()
        guard !katakana.isEmpty else { return nil }
        let mutable = NSMutableString(string: katakana)
        CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)   // katakana → hiragana
        let hiragana = mutable as String
        return hiragana.isEmpty ? nil : hiragana
    }

    // MARK: - Furigana reconcile (pure, dictionary-free)

    /// Reconcile a phonetic `pron` reading against an orthographic `read` reading, both hiragana,
    /// mora by mora. Pure and dictionary-free (unit-tested in isolation).
    ///
    /// The pron×read rule: `pron` is the base — its sound-changes are correct. Where an aligned
    /// mora differs *only* by a long-vowel lengthener — `pron` shows the spoken long vowel
    /// (お after an お-column mora / え after an え-column mora) while `read` shows the orthographic
    /// spelling (…う / …い) — the mora from `read` is taken. When the moras agree they pass through
    /// unchanged (genuine double vowels, e.g. おおきい), and when they differ in any other way the
    /// `pron` mora wins (a true sound-change, e.g. 八百 はっぴゃく vs はちひゃく).
    ///
    /// Fallback: if `pron` and `read` cannot be aligned mora-for-mora (unequal mora count after
    /// small-kana normalization — e.g. differing gemination っ / ん), `pron` is returned unchanged.
    /// The audio-truth is never discarded in favour of a `read` we cannot line up.
    internal static func reconcileFurigana(pron rawPron: String, read rawRead: String) -> String {
        // OpenJTalk `pron` carries an accent-nucleus marker (’ U+2019) that is not a mora. Strip it
        // (and a plain ASCII ' defensively) from both readings first — otherwise it both leaks into
        // the furigana (決して → けっし’て) AND inflates pron's mora count, spuriously tripping the
        // count-mismatch fallback so a spoken long vowel goes uncorrected (ご馳走 → ごち’そお instead
        // of ごちそう). `read` is normally clean; stripping it too is harmless.
        let pron = stripAccentMarks(rawPron)
        let read = stripAccentMarks(rawRead)
        let pronMoras = moras(pron)
        let readMoras = moras(read)
        guard pronMoras.count == readMoras.count else { return pron }   // audio-truth fallback

        var out: [String] = []
        out.reserveCapacity(pronMoras.count)
        for (index, pronMora) in pronMoras.enumerated() {
            let readMora = readMoras[index]
            if pronMora != readMora,
               isLongVowelLengthener(pron: pronMora, read: readMora,
                                     previousVowel: out.last.flatMap(terminalVowel)) {
                out.append(readMora)    // orthographic long-vowel spelling from `read`
            } else {
                out.append(pronMora)    // pron base: sound-changes and genuine double vowels
            }
        }
        return out.joined()
    }

    /// OpenJTalk accent-nucleus markers that ride along in `pron` (’ U+2019, plus a plain ASCII
    /// apostrophe defensively). They are prosody, not moras, and are never wanted in furigana.
    private static let accentMarks: Set<Character> = ["\u{2019}", "\u{0027}"]

    /// Strip the accent-nucleus marker(s) from a hiragana reading.
    private static func stripAccentMarks(_ reading: String) -> String {
        reading.contains(where: accentMarks.contains)
            ? String(reading.filter { !accentMarks.contains($0) })
            : reading
    }

    /// True when the differing pair is exactly a long-vowel lengthener: spoken お / え (in `pron`)
    /// against the orthographic う / い (in `read`) following an お-column / え-column mora.
    private static func isLongVowelLengthener(pron: String, read: String,
                                             previousVowel: Character?) -> Bool {
        switch (pron, read) {
        case ("お", "う"): return previousVowel == "o"   // …お-column お → spelled う
        case ("え", "い"): return previousVowel == "e"   // …え-column え → spelled い
        default: return false
        }
    }

    /// Split a hiragana reading into moras, folding small combining kana (ゃゅょ, ぁぃぅぇぉ, ゎ)
    /// into their preceding base mora. Gemination っ, syllabic ん and chōonpu ー are their own moras.
    private static func moras(_ reading: String) -> [String] {
        var result: [String] = []
        for character in reading {
            if smallCombiningKana.contains(character), let last = result.last {
                result[result.count - 1] = last + String(character)
            } else {
                result.append(String(character))
            }
        }
        return result
    }

    /// The terminal vowel (a/i/u/e/o) of a hiragana mora, or `nil` for moras with no vowel
    /// column (っ, ん, ー, punctuation). Used to detect the phonological long-vowel context.
    private static func terminalVowel(_ mora: String) -> Character? {
        guard let last = mora.last else { return nil }
        return vowelByKana[last]
    }

    private static let smallCombiningKana: Set<Character> = [
        "ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "ゎ"
    ]

    private static let vowelByKana: [Character: Character] = [
        "あ": "a", "か": "a", "さ": "a", "た": "a", "な": "a", "は": "a", "ま": "a", "や": "a",
        "ら": "a", "わ": "a", "が": "a", "ざ": "a", "だ": "a", "ば": "a", "ぱ": "a", "ゃ": "a", "ぁ": "a",
        "い": "i", "き": "i", "し": "i", "ち": "i", "に": "i", "ひ": "i", "み": "i", "り": "i",
        "ぎ": "i", "じ": "i", "ぢ": "i", "び": "i", "ぴ": "i", "ぃ": "i",
        "う": "u", "く": "u", "す": "u", "つ": "u", "ぬ": "u", "ふ": "u", "む": "u", "ゆ": "u",
        "る": "u", "ぐ": "u", "ず": "u", "づ": "u", "ぶ": "u", "ぷ": "u", "ゅ": "u", "ぅ": "u",
        "え": "e", "け": "e", "せ": "e", "て": "e", "ね": "e", "へ": "e", "め": "e", "れ": "e",
        "げ": "e", "ぜ": "e", "で": "e", "べ": "e", "ぺ": "e", "ぇ": "e",
        "お": "o", "こ": "o", "そ": "o", "と": "o", "の": "o", "ほ": "o", "も": "o", "よ": "o",
        "ろ": "o", "を": "o", "ご": "o", "ぞ": "o", "ど": "o", "ぼ": "o", "ぽ": "o", "ょ": "o", "ぉ": "o"
    ]
}

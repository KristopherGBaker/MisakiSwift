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

/// One analyzed word from the OpenJTalk frontend: its surface form and orthographic
/// hiragana reading (empty when the word has no reading, e.g. punctuation).
public struct OpenJTalkWord: Sendable, Hashable {
    public let surface: String
    public let reading: String

    public init(surface: String, reading: String) {
        self.surface = surface
        self.reading = reading
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
            let katakana = word.read
            guard !katakana.isEmpty else {
                return OpenJTalkWord(surface: word.surface, reading: "")
            }
            let mutable = NSMutableString(string: katakana)
            CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)
            return OpenJTalkWord(surface: word.surface, reading: mutable as String)
        }
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
}

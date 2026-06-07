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
    public func hiraganaReading(for text: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        let katakana = frontend.runFrontend(text).map(\.pron).joined()
        guard !katakana.isEmpty else { return nil }
        let mutable = NSMutableString(string: katakana)
        CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)   // katakana → hiragana
        let hiragana = mutable as String
        return hiragana.isEmpty ? nil : hiragana
    }
}

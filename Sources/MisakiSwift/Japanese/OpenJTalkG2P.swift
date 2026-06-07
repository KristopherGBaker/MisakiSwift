//
//  MisakiSwift — OpenJTalk-backed Japanese G2P
//
//  The Phase-2 upgrade over `JapaneseG2P` (the pure-Apple Phase-1 fallback). It
//  drives the vendored Open JTalk text-processing frontend (`COpenJTalk`) for true
//  morphological analysis with an accent dictionary, fixing the reading and
//  particle errors `CFStringTokenizer` makes (私→ワタシ not ワタクシ, contextual
//  は→ワ / へ→エ, counters like 3日→ミッカ, 100円→ヒャクエン) and exposing
//  phonemic pitch accent (箸 acc=1 vs 橋 acc=2).
//
//  IPA is produced by reusing the model-faithful `KanaToIPA` table (cutlet HEPBURN):
//  OpenJTalk's katakana `pron` → hiragana → IPA. We deliberately do NOT port
//  misaki ja.py's own `M2P` table, whose symbols (`g`, `K`, `ᶄ`, …) are largely
//  out-of-vocab for Aoede's Kokoro — they would be silently dropped by the
//  tokenizer and desync durations from tokens.
//
//  Pitch: misaki's accent loop (ja.py ~276–356) is ported to compute a per-mora
//  accent code, but downstep is NOT injected into the phoneme stream by default —
//  the stream stays clean in-vocab IPA (`↓` injection is gated behind
//  `injectDownstep`, default off, pending an audio A/B test). misaki's parallel
//  `_ ^ - j` pitch track is never emitted (those chars are out-of-vocab).
//
//  Contract with KokoroSwift's TimestampPredictor (identical to JapaneseG2P):
//  the returned phoneme string equals the in-order concatenation of each token's
//  `phonemes` + `whitespace`, every character is in-vocab, and empty-phoneme +
//  empty-whitespace tokens are omitted.
//

import Foundation
import MLXUtilsLibrary

public final class OpenJTalkG2P {

    /// When true, inject the Kokoro-vocab downstep marker `↓` at the accent nucleus
    /// (the mora carrying accent code 3). Default off: until an audio A/B shows the
    /// JA model consumes pitch markers, the phoneme stream stays clean IPA and
    /// accent is carried only as metadata. `↑` is not in vocab, so only `↓` is ever
    /// emitted.
    public var injectDownstep: Bool

    private let frontend: OJTFrontend

    /// Create a G2P bound to an Open JTalk UTF-8 dictionary directory.
    /// - Returns: `nil` if the dictionary cannot be loaded (caller falls back to
    ///   `JapaneseG2P`).
    public init?(dictionaryDirectory: URL, injectDownstep: Bool = false) {
        guard let frontend = OJTFrontend(dictionaryDirectory: dictionaryDirectory) else { return nil }
        self.frontend = frontend
        self.injectDownstep = injectDownstep
    }

    /// One analyzed word: the frontend's reading/accent plus the derived moras,
    /// per-mora accent codes and IPA. Internal so tests can assert on the port.
    struct AnalyzedWord {
        var surface: String
        var pron: String
        var pos: String
        var acc: Int
        var moraSize: Int
        var chainFlag: Bool
        var moras: [String]
        var accents: [Int]
        var phonemes: String?
    }

    // MARK: - Public API

    /// Convert Japanese text to a Kokoro-ready phoneme string plus per-token timing
    /// breakdown. Signature matches `JapaneseG2P.phonemize(text:)`.
    public func phonemize(text: String) -> (String, [MToken]) {
        let words = analyze(text)
        let tokens = makeTokens(words, in: text)
        let phonemeString = tokens.map { ($0.phonemes ?? "") + $0.whitespace }.joined()
        return (phonemeString, tokens)
    }

    // MARK: - Analysis + accent port (misaki ja.py ~276–356)

    /// Run the frontend and compute moras / per-mora accent codes / IPA per word.
    func analyze(_ text: String) -> [AnalyzedWord] {
        let raw = frontend.runFrontend(text)
        var words: [AnalyzedWord] = []

        // Accent-loop carry state (misaki: last_a, acc, mcount across chained phrases).
        var lastA = 0
        var acc: Int?
        var mcount = 0

        for (index, word) in raw.enumerated() {
            let moras = word.moraSize > 0 ? Self.pronToMoras(word.pron) : []

            // chain_flag: only chains when this AND the previous word have moras and
            // the frontend flagged attach (==1) or this word starts with a long vowel.
            let prevHasMoras = index > 0 && raw[index - 1].moraSize > 0
            let chainFlag = word.moraSize > 0 && prevHasMoras
                && (word.chainFlag == 1 || moras.first == "ー")

            if !chainFlag {
                acc = nil
                mcount = 0
            }
            if acc == nil { acc = word.acc }
            let accValue = acc ?? 0

            var accents: [Int] = []
            for _ in moras {
                mcount += 1
                let code: Int
                if accValue == 0 {
                    code = mcount == 1 ? 0 : (lastA == 0 ? 1 : 2)
                } else if accValue == mcount {
                    code = 3
                } else if mcount > 1 && mcount < accValue {
                    code = lastA == 0 ? 1 : 2
                } else {
                    code = 0
                }
                accents.append(code)
                lastA = code
            }

            let phonemes = moras.isEmpty ? nil : ipa(moras: moras, accents: accents)
            words.append(AnalyzedWord(
                surface: word.surface, pron: word.pron, pos: word.pos,
                acc: word.acc, moraSize: word.moraSize, chainFlag: chainFlag,
                moras: moras, accents: accents, phonemes: phonemes))
        }
        return words
    }

    /// Split a katakana `pron` into moras, mirroring misaki's `pron2moras`: keep
    /// only characters the mora table knows, greedily forming two-kana digraphs.
    static func pronToMoras(_ pron: String) -> [String] {
        var moras: [String] = []
        for character in pron {
            let kana = String(character)
            guard Self.isMoraChar(kana) else { continue }
            if let last = moras.last, Self.isMoraChar(last + kana) {
                moras[moras.count - 1] = last + kana
            } else {
                moras.append(kana)
            }
        }
        return moras
    }

    /// Whether a 1- or 2-char katakana string is a valid mora (in the hiragana IPA
    /// table after conversion, or a special mark ー/ッ/ン).
    private static func isMoraChar(_ kana: String) -> Bool {
        if kana == "ー" || kana == "ッ" || kana == "ン" { return true }
        let hira = KanaToIPA.katakanaToHiragana(kana)
        if hira.count == 1, let first = hira.first { return KanaIPA.single[first] != nil }
        if hira.count == 2 { return KanaIPA.digraph[hira] != nil }
        return false
    }

    /// Convert a word's moras to IPA, optionally injecting `↓` at the nucleus.
    private func ipa(moras: [String], accents: [Int]) -> String {
        // Convert the whole katakana mora sequence at once so cross-mora context
        // (digraphs, ん assimilation, ー lengthening) is handled by KanaToIPA.
        let hiragana = KanaToIPA.katakanaToHiragana(moras.joined())
        let base = KanaToIPA.ipa(forHiragana: hiragana)
        guard injectDownstep else { return base }
        // Downstep injection: re-render mora by mora so `↓` lands after the nucleus.
        var out = ""
        for (mora, code) in zip(moras, accents) {
            out += KanaToIPA.ipa(forHiragana: KanaToIPA.katakanaToHiragana(mora))
            if code == 3 { out += "↓" }
        }
        return out
    }

    // MARK: - Token assembly (honours the TimestampPredictor contract)

    private func makeTokens(_ words: [AnalyzedWord], in text: String) -> [MToken] {
        var tokens: [MToken] = []
        var cursor = text.startIndex

        for word in words {
            // Map the surface back to a range in the input (sequential search). If
            // the frontend normalized the surface away (e.g. digit folding), use a
            // zero-width range at the cursor — still a valid Range<String.Index>.
            let range: Range<String.Index>
            if let found = text.range(of: word.surface, range: cursor..<text.endIndex) {
                range = found
                cursor = found.upperBound
            } else {
                range = cursor..<cursor
            }

            if let phonemes = word.phonemes, !phonemes.isEmpty {
                // Separate accent phrases with a space (chain breaks); attach within.
                let whitespace = word.chainFlag ? "" : " "
                if !word.chainFlag, let last = tokens.last, last.whitespace.isEmpty {
                    last.whitespace = " "
                }
                tokens.append(MToken(
                    text: word.surface, tokenRange: range, whitespace: whitespace, phonemes: phonemes))
            } else if let mapped = Self.punctuation(word.surface) {
                if let last = tokens.last { last.whitespace = "" }
                tokens.append(MToken(
                    text: word.surface, tokenRange: range, whitespace: " ", phonemes: mapped))
            }
            // else: no phonemes and not punctuation → omit (empty-phoneme +
            // empty-whitespace would stall the predictor).
        }

        // No trailing pause at the very end of the utterance.
        tokens.last?.whitespace = ""
        return tokens
    }

    /// Japanese punctuation → in-vocab equivalents (subset shared with JapaneseG2P).
    private static func punctuation(_ surface: String) -> String? {
        guard surface.count == 1, let character = surface.first else { return nil }
        return punctuationMap[character]
    }

    private static let punctuationMap: [Character: String] = [
        "。": ".", "．": ".", "、": ",", "，": ",", "！": "!", "？": "?",
        "：": ":", "；": ";", "（": "(", "）": ")", "《": "(", "》": ")",
        "「": "\u{201C}", "」": "\u{201D}", "『": "\u{201C}", "』": "\u{201D}",
        "«": "\u{201C}", "»": "\u{201D}", "・": " ", "…": "…", "—": "—",
        "～": "—", "〜": "—"
    ]
}

//
//  MisakiSwift — Japanese G2P
//
//  A pure-Apple Japanese grapheme-to-phoneme front end for the Kokoro
//  multilingual model. It produces the same IPA phoneme inventory the reference
//  Python `misaki[ja]` (cutlet path) emits — every symbol is present in Kokoro's
//  vocab — using only system frameworks, with **no** native morphological-
//  analyzer or dictionary dependency:
//
//    1. `CFStringTokenizer` (ja_JP, word-boundary) segments the text and yields a
//       Hepburn *romaji* reading per token from the system Japanese dictionary
//       (the same engine the IME uses), resolving kanji readings.
//    2. ICU `Latin-Hiragana` (`CFStringTransform`) turns that romaji into
//       hiragana — including gemination (がっこう), youon (ひゃく), n' (こんにちは),
//       and CFStringTokenizer's `~tsu` sokuon notation (→ っ).
//    3. `kanaToIPA` (a faithful port of cutlet's `_get_single_mapping`) maps the
//       hiragana to IPA via `KanaIPA`, applying digraphs, sutegana, sokuon (ʔ),
//       chōonpu (ː) and context-sensitive ん assimilation (m / ŋ / ɲ / n / ɴ).
//
//  Known Phase-1 limitations (a future OpenJTalk-backed deriver addresses these):
//    • No pitch accent — Japanese pitch is phonemic (箸 vs 橋) so some words read
//      flat. Intonation is left to Kokoro's prosody predictor.
//    • Particle quirks: standalone は→わ and へ→え are corrected heuristically
//      (a lone-token reading), but contextual cases still need POS analysis.
//    • A handful of less-common readings (私→watakushi) and counter readings
//      (…日→ka) follow the system dictionary's first reading.
//    • Embedded ASCII/English runs are skipped (silent) rather than phonemized.
//
//  The contract with KokoroSwift's `TimestampPredictor` is: the returned phoneme
//  string equals the concatenation, in order, of each token's `phonemes` followed
//  by its `whitespace`, and every character is in-vocab. Word timing and karaoke
//  highlighting fall out of that for free.
//

import Foundation
import MLXUtilsLibrary

public final class JapaneseG2P {
    public init() {}

    private static let sutegana: Set<Character> = ["ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]

    /// Particles whose spoken reading differs from the kana, keyed by the lone
    /// token surface: は→わ, へ→え. (を→お is already handled by the kana table.)
    private static let particleReading: [String: String] = ["は": "わ", "へ": "え"]

    /// Japanese punctuation → in-vocab ASCII/quote equivalents (subset of cutlet's
    /// symbol table restricted to characters Kokoro's vocab contains).
    private static let punctuation: [Character: String] = [
        "。": ".", "．": ".", "、": ",", "，": ",", "！": "!", "？": "?",
        "：": ":", "；": ";", "（": "(", "）": ")", "《": "(", "》": ")",
        "「": "\u{201C}", "」": "\u{201D}", "『": "\u{201C}", "』": "\u{201D}",
        "«": "\u{201C}", "»": "\u{201D}", "・": " ", "…": "…", "—": "—",
        "～": "—", "〜": "—"
    ]

    // MARK: - Public API

    /// Convert Japanese text to a Kokoro-ready phoneme string plus the per-token
    /// breakdown KokoroSwift uses to derive word timestamps.
    public func phonemize(text: String) -> (String, [MToken]) {
        let tokens = makeTokens(text)
        let phonemeString = tokens.map { ($0.phonemes ?? "") + $0.whitespace }.joined()
        return (phonemeString, tokens)
    }

    // MARK: - Tokenization

    private func makeTokens(_ text: String) -> [MToken] {
        let cf = text as CFString
        let fullRange = CFRangeMake(0, CFStringGetLength(cf))
        let locale = CFLocaleCreate(nil, CFLocaleIdentifier("ja_JP" as CFString))
        guard let tokenizer = CFStringTokenizerCreate(
            nil, cf, fullRange, kCFStringTokenizerUnitWordBoundary, locale) else { return [] }

        var tokens: [MToken] = []
        var status = CFStringTokenizerAdvanceToNextToken(tokenizer)
        while status != [] {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let surface = CFStringCreateWithSubstring(nil, cf, cfRange) as String

            guard let phonemes = phonemes(for: surface, tokenizer: tokenizer), !phonemes.isEmpty else {
                status = CFStringTokenizerAdvanceToNextToken(tokenizer)
                continue
            }

            let range = stringRange(cfRange, in: text)
            let isPunct = surface.unicodeScalars.allSatisfy { !CharacterSet.alphanumerics.contains($0) }
                && Self.punctuation[surface.first ?? " "] != nil
            // Attach clause punctuation to the preceding word (no leading space).
            if isPunct, let last = tokens.last {
                last.whitespace = ""
            }
            tokens.append(MToken(text: surface, tokenRange: range, whitespace: " ", phonemes: phonemes))

            status = CFStringTokenizerAdvanceToNextToken(tokenizer)
        }

        // No trailing pause at the very end of the utterance.
        tokens.last?.whitespace = ""
        return tokens
    }

    /// Map a single CFStringTokenizer token's surface to IPA.
    private func phonemes(for surface: String, tokenizer: CFStringTokenizer) -> String? {
        if let first = surface.first, surface.count == 1, let mapped = Self.punctuation[first] {
            return mapped
        }
        // Topic/direction particles: written は/へ but read わ/え. CFStringTokenizer
        // surfaces a particle as its own single-character token (vs. inside a word)
        // and gives the literal reading; correct the two that differ. Heuristic —
        // proper part-of-speech particle detection is Phase 2 (OpenJTalk).
        if let particle = Self.particleReading[surface] {
            return kanaToIPA(particle)
        }
        if let value = Int(surface) {
            return kanaToIPA(JapaneseNumbers.hiragana(for: value))
        }
        if surface.allSatisfy({ $0.isASCII }) {
            return nil // embedded ASCII/English — skipped in Phase 1
        }
        let latin = CFStringTokenizerCopyCurrentTokenAttribute(
            tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
        guard let latin, !latin.isEmpty else { return nil }
        return kanaToIPA(Self.romajiToHiragana(latin))
    }

    // MARK: - Romaji → Hiragana (ICU)

    static func romajiToHiragana(_ romaji: String) -> String {
        let mutable = NSMutableString(string: romaji) as CFMutableString
        CFStringTransform(mutable, nil, kCFStringTransformLatinHiragana, false)
        return mutable as String
    }

    // MARK: - Hiragana → IPA (port of cutlet `_get_single_mapping`)

    func kanaToIPA(_ hira: String) -> String {
        let chars = Array(hira)
        var out = ""
        for i in 0..<chars.count {
            let kk = chars[i]
            let pk: Character? = i > 0 ? chars[i - 1] : nil
            let nk: Character? = i < chars.count - 1 ? chars[i + 1] : nil

            // Digraph with the previous kana → emitted now (was deferred last step).
            if let pk, let mapped = KanaIPA.digraph[String([pk, kk])] { out += mapped; continue }
            // Digraph with the next kana → defer; emit on the next iteration.
            if let nk, KanaIPA.digraph[String([kk, nk])] != nil { continue }
            // A base kana followed by a sutegana that is not a known digraph:
            // drop the base's vowel and append the small-kana vowel.
            if let nk, Self.sutegana.contains(nk), kk != "っ",
               let base = KanaIPA.single[kk], let small = KanaIPA.single[nk] {
                out += String(base.dropLast()) + small
                continue
            }
            if Self.sutegana.contains(kk) { continue }
            if kk == "ー" { out += "ː"; continue }
            if kk == "っ" { out += "ʔ"; continue }
            if kk == "ん" { out += moraicNasal(next: nk, at: i, in: chars); continue }
            if let value = KanaIPA.single[kk] { out += value }
        }
        return out
    }

    /// Context-sensitive realization of ん based on the following sound.
    private func moraicNasal(next nk: Character?, at index: Int, in chars: [Character]) -> String {
        guard let nk, let following = mapping(of: nk, at: index, in: chars), let first = following.first else {
            return "ɴ"
        }
        if "mpb".contains(first) { return "m" }
        if "kɡ".contains(first) { return "ŋ" }
        if following.hasPrefix("ɲ") || following.hasPrefix("ʨ") || following.hasPrefix("ʥ") { return "ɲ" }
        if "ntdɾz".contains(first) { return "n" }
        return "ɴ"
    }

    /// Best-effort IPA of the kana after ん (honouring a possible digraph) so its
    /// leading consonant can drive nasal assimilation.
    private func mapping(of nk: Character, at index: Int, in chars: [Character]) -> String? {
        if index + 2 < chars.count, let digraph = KanaIPA.digraph[String([nk, chars[index + 2]])] {
            return digraph
        }
        return KanaIPA.single[nk]
    }

    // MARK: - Ranges

    private func stringRange(_ cfRange: CFRange, in text: String) -> Range<String.Index> {
        let lower = String.Index(utf16Offset: cfRange.location, in: text)
        let upper = String.Index(utf16Offset: cfRange.location + cfRange.length, in: text)
        return lower..<upper
    }
}

//
//  MisakiSwift — shared hiragana → IPA conversion
//
//  A faithful port of cutlet's `_get_single_mapping`, factored out of
//  `JapaneseG2P` so the OpenJTalk-backed deriver (`OpenJTalkG2P`) reuses the exact
//  same model-faithful IPA inventory rather than inventing its own. It applies
//  digraphs, sutegana, sokuon (ʔ), chōonpu (ː) and context-sensitive ん
//  assimilation (m / ŋ / ɲ / n / ɴ). Input must be hiragana — katakana readings
//  (e.g. OpenJTalk's `pron`) are converted first via `katakanaToHiragana`.
//

import Foundation

public enum KanaToIPA {

    private static let sutegana: Set<Character> = ["ゃ", "ゅ", "ょ", "ぁ", "ぃ", "ぅ", "ぇ", "ぉ"]

    /// Convert a hiragana string to Kokoro-vocab IPA.
    public static func ipa(forHiragana hira: String) -> String {
        let chars = Array(hira)
        var out = ""
        for index in 0..<chars.count {
            let kk = chars[index]
            let pk: Character? = index > 0 ? chars[index - 1] : nil
            let nk: Character? = index < chars.count - 1 ? chars[index + 1] : nil

            // Digraph with the previous kana → emitted now (was deferred last step).
            if let pk, let mapped = KanaIPA.digraph[String([pk, kk])] { out += mapped; continue }
            // Digraph with the next kana → defer; emit on the next iteration.
            if let nk, KanaIPA.digraph[String([kk, nk])] != nil { continue }
            // A base kana followed by a sutegana that is not a known digraph:
            // drop the base's vowel and append the small-kana vowel.
            if let nk, sutegana.contains(nk), kk != "っ",
               let base = KanaIPA.single[kk], let small = KanaIPA.single[nk] {
                out += String(base.dropLast()) + small
                continue
            }
            if sutegana.contains(kk) { continue }
            if kk == "ー" { out += "ː"; continue }
            if kk == "っ" { out += "ʔ"; continue }
            if kk == "ん" { out += moraicNasal(next: nk, at: index, in: chars); continue }
            if let value = KanaIPA.single[kk] { out += value }
        }
        return out
    }

    /// Convert katakana to hiragana by the fixed −0x60 codepoint offset (U+30A1…
    /// U+30F6 → U+3041…U+3096). The prolonged-sound mark ー (U+30FC) and any
    /// non-katakana characters (accent marks like ’, punctuation) pass through
    /// unchanged; `ipa(forHiragana:)` then handles ー and ignores the rest.
    public static func katakanaToHiragana(_ katakana: String) -> String {
        var out = ""
        out.reserveCapacity(katakana.count)
        for scalar in katakana.unicodeScalars {
            if scalar.value >= 0x30A1 && scalar.value <= 0x30F6 {
                out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x60)!)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Context-sensitive realization of ん based on the following sound.
    private static func moraicNasal(next nk: Character?, at index: Int, in chars: [Character]) -> String {
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
    private static func mapping(of nk: Character, at index: Int, in chars: [Character]) -> String? {
        if index + 2 < chars.count, let digraph = KanaIPA.digraph[String([nk, chars[index + 2]])] {
            return digraph
        }
        return KanaIPA.single[nk]
    }
}

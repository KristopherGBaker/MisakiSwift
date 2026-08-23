import Foundation

/// Katakana to hiragana, in pure Swift.
///
/// This replaces `CFStringTransform(_, kCFStringTransformHiraganaKatakana, true)`, which is
/// CoreFoundation and therefore Apple-only. Those three calls were the last Apple dependency
/// in the Open JTalk reading path, and they stood between the Japanese frontend and Android.
///
/// The mapping is a fixed scalar offset: the katakana block U+30A1...U+30F6 sits exactly
/// 0x60 above the matching hiragana, and the two iteration marks pair the same way. Anything
/// else, including the prolonged sound mark ー and the middle dot, is passed through
/// unchanged, which is what the CoreFoundation transform does for them too.
///
/// Open JTalk emits full-width katakana, so that block is the whole input domain in practice.
/// `KanaConversionTests` asserts agreement with `CFStringTransform` across it, on macOS, so
/// the claim is measured rather than assumed.
public enum KanaConversion {
    /// The hiragana form of `katakana`. Non-katakana scalars are returned unchanged.
    public static func hiragana(fromKatakana katakana: String) -> String {
        guard !katakana.isEmpty else { return "" }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(katakana.unicodeScalars.count)
        for scalar in katakana.unicodeScalars {
            if scalar.value == 0x30FC {
                // The prolonged sound mark is written out as the vowel it lengthens, which is
                // what CFStringTransform does and therefore what the app already shows:
                // コーヒー reads こおひい, not こーひー. With nothing before it there is no
                // vowel to copy, so it is passed through.
                if let vowel = out.last.flatMap(Self.vowel(of:)) {
                    out.append(vowel)
                } else {
                    out.append(scalar)
                }
            } else if let expansion = Self.expansions[scalar.value] {
                out.append(contentsOf: expansion)
            } else {
                out.append(hiragana(from: scalar) ?? scalar)
            }
        }
        return String(out)
    }

    /// Katakana whose hiragana form is more than one scalar, so a fixed offset cannot express
    /// it. The parity test against `CFStringTransform` found every one of these; they are
    /// outside Open JTalk's output in practice, but a silent divergence here would surface as
    /// wrong furigana rather than as a failure, which is the worst way to be wrong.
    ///
    /// ヷヸヹヺ have no precomposed hiragana, so they decompose to the plain kana plus the
    /// combining voiced mark U+3099. ヿ is the KATAKANA DIGRAPH KOTO and spells out こと.
    private static let expansions: [UInt32: [Unicode.Scalar]] = [
        0x30F7: [.init(0x308F)!, .init(0x3099)!],   // ヷ -> わ + combining dakuten
        0x30F8: [.init(0x3090)!, .init(0x3099)!],   // ヸ -> ゐ + combining dakuten
        0x30F9: [.init(0x3091)!, .init(0x3099)!],   // ヹ -> ゑ + combining dakuten
        0x30FA: [.init(0x3092)!, .init(0x3099)!],   // ヺ -> を + combining dakuten
        0x30FF: [.init(0x3053)!, .init(0x3068)!],   // ヿ -> こと
        // ヵ and ヶ are small katakana whose conventional hiragana is the FULL-SIZE kana, not
        // the small ゕ/ゖ a plain offset produces.
        0x30F5: [.init(0x304B)!],                   // ヵ -> か
        0x30F6: [.init(0x3051)!]                    // ヶ -> け
    ]

    /// The vowel a hiragana scalar ends in, for expanding a prolonged sound mark. `nil` for
    /// anything with no vowel of its own (ん, っ, punctuation, non-kana).
    private static func vowel(of scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let a: Set<UInt32> = [0x3042, 0x304B, 0x304C, 0x3055, 0x3056, 0x305F, 0x3060, 0x306A,
                              0x306F, 0x3070, 0x3071, 0x307E, 0x3084, 0x3089, 0x308F, 0x3041,
                              0x3083, 0x308E, 0x3095]
        let i: Set<UInt32> = [0x3044, 0x304D, 0x304E, 0x3057, 0x3058, 0x3061, 0x3062, 0x306B,
                              0x3072, 0x3073, 0x3074, 0x307F, 0x308A, 0x3090, 0x3043]
        let u: Set<UInt32> = [0x3046, 0x304F, 0x3050, 0x3059, 0x305A, 0x3064, 0x3065, 0x306C,
                              0x3075, 0x3076, 0x3077, 0x3080, 0x3086, 0x308B, 0x3045, 0x3085,
                              0x3094]
        let e: Set<UInt32> = [0x3048, 0x3051, 0x3052, 0x305B, 0x305C, 0x3066, 0x3067, 0x306D,
                              0x3078, 0x3079, 0x307A, 0x3081, 0x308C, 0x3091, 0x3047, 0x3096]
        let o: Set<UInt32> = [0x304A, 0x3053, 0x3054, 0x305D, 0x305E, 0x3068, 0x3069, 0x306E,
                              0x307B, 0x307C, 0x307D, 0x3082, 0x3088, 0x308D, 0x3092, 0x3049,
                              0x3087]
        let value = scalar.value
        if a.contains(value) { return Unicode.Scalar(0x3042) }
        if i.contains(value) { return Unicode.Scalar(0x3044) }
        if u.contains(value) { return Unicode.Scalar(0x3046) }
        if e.contains(value) { return Unicode.Scalar(0x3048) }
        if o.contains(value) { return Unicode.Scalar(0x304A) }
        return nil
    }

    /// The hiragana scalar for a katakana one, or nil when it is not katakana.
    private static func hiragana(from scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar.value {
        // ァ...ヶ. Stops at U+30F6 deliberately: U+30F7...U+30FA (ヷヸヹヺ) have no hiragana
        // counterpart, and U+30FB/U+30FC are the middle dot and the prolonged sound mark,
        // which are shared punctuation rather than katakana letters.
        case 0x30A1...0x30F6,
             // ヽヾ, the katakana iteration marks, pair with ゝゞ at the same offset.
             0x30FD...0x30FE:
            return Unicode.Scalar(scalar.value - 0x60)
        default:
            return nil
        }
    }
}

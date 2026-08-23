import Foundation
import Testing
@testable import MisakiJapanese

/// `KanaConversion` replaced three `CFStringTransform` calls, so the bar is agreement with
/// the thing it replaced, measured rather than asserted. CoreFoundation is available here on
/// macOS, which is exactly why the comparison belongs here: on Android there is nothing to
/// compare against, and a divergence would surface as wrong furigana rather than a failure.
@Suite("Katakana to hiragana")
struct KanaConversionTests {
    /// The reference: what the old code did.
    private func coreFoundation(_ katakana: String) -> String {
        let mutable = NSMutableString(string: katakana)
        CFStringTransform(mutable, nil, kCFStringTransformHiraganaKatakana, true)
        return mutable as String
    }

    @Test("agrees with CFStringTransform across the whole katakana block")
    func matchesCoreFoundationOverTheBlock() {
        for value in 0x30A1...0x30FF {
            guard let scalar = Unicode.Scalar(value) else { continue }
            let input = String(Character(scalar))
            #expect(KanaConversion.hiragana(fromKatakana: input) == coreFoundation(input),
                    "diverged at U+\(String(value, radix: 16, uppercase: true))")
        }
    }

    @Test("agrees on real Open JTalk output, which is what actually flows through")
    func matchesOnRealReadings() {
        // Readings as Open JTalk emits them: full-width katakana, with a long mark and a
        // sokuon, plus a mixed string to prove non-kana is passed through untouched.
        for input in ["センセイ", "ガッコウ", "コンニチハ", "ヒャク", "コーヒー",
                      "トウキョウ・オオサカ", "ABCカタカナ123", "", "ひらがな"] {
            #expect(KanaConversion.hiragana(fromKatakana: input) == coreFoundation(input),
                    "diverged on \(input)")
        }
    }

    @Test("converts, rather than passing everything through")
    func actuallyConverts() {
        // A pass-through implementation would satisfy the parity tests only if
        // CFStringTransform were also a no-op, so pin the conversion itself too.
        #expect(KanaConversion.hiragana(fromKatakana: "センセイ") == "せんせい")
        #expect(KanaConversion.hiragana(fromKatakana: "ガッコウ") == "がっこう")
        // The prolonged sound mark is written out as the vowel it lengthens. This assertion
        // originally expected こーひー, which was simply wrong about the behaviour being
        // replaced: CFStringTransform expands it, so that is what the app already shows.
        #expect(KanaConversion.hiragana(fromKatakana: "コーヒー") == "こおひい")
        #expect(KanaConversion.hiragana(fromKatakana: "ラーメン") == "らあめん")
    }
}

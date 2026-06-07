import Foundation

/// The Kokoro multilingual model's single-character vocabulary (114 symbols),
/// copied verbatim from `kokoro-ios/Resources/config.json` so the G2P contract
/// tests can assert that every emitted phoneme character is in-vocab without
/// reaching across packages. Out-of-vocab characters are silently dropped by the
/// tokenizer, which desyncs per-phoneme durations from tokens.
///
/// Built from Unicode *scalars* (not `Character`s): the vocab includes the
/// standalone combining tilde `̃` (U+0303) and `ː` (U+02D0) adjacently, which
/// Swift would otherwise fuse into one grapheme cluster `ː̃`.
enum KokoroVocabFixture {
    private static let raw =
        " !\"(),.:;?AIOQSTWYabcdefhijklmnopqrstuvwxyz" +
        "æçðøŋœɐɑɒɔɕɖəɚɛɜɟɡɣɤɥɨɪɯɰɲɳɴɸɹɻɽɾʁʂʃʈʊʋʌʎʒʔʝ" +
        "ʣʤʥʦʧʨʰʲˈˌː\u{0303}βθχᵊᵝᵻ—“”…→↓↗↘ꭧ"

    static let scalars: Set<Unicode.Scalar> = Set(raw.unicodeScalars)

    /// Whether every Unicode scalar of `character` is in the vocab. A phoneme
    /// "character" the G2P emits may be a multi-scalar grapheme (e.g. a base
    /// vowel + combining tilde), all parts of which must be in-vocab.
    static func contains(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalars.contains($0) }
    }
}

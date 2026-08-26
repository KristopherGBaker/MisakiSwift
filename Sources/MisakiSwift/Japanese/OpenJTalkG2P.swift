//
//  MisakiSwift — OpenJTalk-backed Japanese G2P (MToken adapter)
//
//  The G2P itself lives in MisakiJapanese (`OpenJTalkKokoroG2P`), MLX-free so the
//  Android port can drive the same phonemizer. This wrapper keeps the historical
//  class name and the `(String, [MToken])` signature the Apple Kokoro pipeline
//  consumes, adding back the token ranges MToken carries.
//

import Foundation
import MisakiJapanese
import MLXUtilsLibrary

public final class OpenJTalkG2P {
    private let core: OpenJTalkKokoroG2P

    public var injectDownstep: Bool {
        get { core.injectDownstep }
        set { core.injectDownstep = newValue }
    }

    public init?(dictionaryDirectory: URL, injectDownstep: Bool = false) {
        guard let core = OpenJTalkKokoroG2P(
            dictionaryDirectory: dictionaryDirectory, injectDownstep: injectDownstep) else {
            return nil
        }
        self.core = core
    }

    public func phonemize(text: String) -> (String, [MToken]) {
        let (phonemes, coreTokens) = core.phonemize(text: text)
        var tokens: [MToken] = []
        var cursor = text.startIndex
        for token in coreTokens {
            // Map the surface back to a range in the input (sequential search). If
            // the frontend normalized the surface away (e.g. digit folding), use a
            // zero-width range at the cursor — still a valid Range<String.Index>.
            let range: Range<String.Index>
            if let found = text.range(of: token.text, range: cursor..<text.endIndex) {
                range = found
                cursor = found.upperBound
            } else {
                range = cursor..<cursor
            }
            tokens.append(MToken(
                text: token.text, tokenRange: range,
                whitespace: token.whitespace, phonemes: token.phonemes))
        }
        return (phonemes, tokens)
    }
}

//
//  MisakiSwift — Japanese G2P selection
//
//  A small seam that lets KokoroSwift prefer the OpenJTalk-backed `OpenJTalkG2P`
//  when its dictionary is available, and otherwise fall back to the pure-Apple
//  `JapaneseG2P` — without the caller knowing which engine ran. The app configures
//  the dictionary location once (after lazy download); `makeJapanesePhonemizer()`
//  resolves the best available engine at `setLanguage(.ja)` time.
//

import Foundation
import MLXUtilsLibrary

/// The common Japanese G2P interface (both engines already expose this signature).
public protocol JapanesePhonemizer: AnyObject {
    func phonemize(text: String) -> (String, [MToken])
}

extension JapaneseG2P: JapanesePhonemizer {}
extension OpenJTalkG2P: JapanesePhonemizer {}

/// Resolve the best available Japanese phonemizer: OpenJTalk when its dictionary
/// is configured and loads, otherwise the pure-Apple `JapaneseG2P`.
public func makeJapanesePhonemizer() -> JapanesePhonemizer {
    if let directory = JapaneseG2PConfiguration.dictionaryDirectory,
       FileManager.default.fileExists(atPath: directory.appendingPathComponent("sys.dic").path),
       let openJTalk = OpenJTalkG2P(
        dictionaryDirectory: directory,
        injectDownstep: JapaneseG2PConfiguration.injectDownstep) {
        return openJTalk
    }
    return JapaneseG2P()
}

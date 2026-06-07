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

/// Process-wide configuration for the OpenJTalk Japanese G2P. The app sets
/// `dictionaryDirectory` after ensuring the UTF-8 `open_jtalk_dic` is present
/// (download-on-first-use); when unset or absent, Japanese falls back to
/// `JapaneseG2P`.
public enum JapaneseG2PConfiguration {
    /// Directory containing the Open JTalk UTF-8 dictionary (sys.dic etc.), or
    /// `nil` to force the pure-Apple fallback. Set once at startup; read on the
    /// synthesis queue.
    nonisolated(unsafe) public static var dictionaryDirectory: URL?

    /// Whether to inject the `↓` downstep marker into the phoneme stream. Default
    /// off (clean IPA) pending an audio A/B test that the JA model consumes it.
    nonisolated(unsafe) public static var injectDownstep: Bool = false
}

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

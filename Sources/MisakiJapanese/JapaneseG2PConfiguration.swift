import Foundation

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

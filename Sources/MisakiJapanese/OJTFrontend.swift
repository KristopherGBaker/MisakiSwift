// NOTE: `OJTFrontend` and `OJTWord` are `public` because `OpenJTalkG2P`, which stays in the
// MLX-dependent `MisakiSwift` module, drives them. They are SPI for that sibling rather than
// API for applications.
//
//  MisakiSwift — Swift wrapper over the COpenJTalk C frontend
//
//  Owns an `ojt_frontend` handle (one MeCab dictionary load, reused across calls)
//  and exposes `runFrontend(_:)` returning the per-word readings/accent the G2P
//  port needs. The underlying frontend mutates per-call NJD/Mecab state, so calls
//  must be serialized by the caller (the speech provider already serializes
//  synthesis on a single queue).
//

import COpenJTalk
import Foundation

/// One NJD word, copied out of the C result into Swift-owned storage.
public struct OJTWord {
    public var surface: String
    /// NJD `orig` — the dictionary base form (食べました→食べる), useful for JMDict lookup.
    public var base: String
    public var pron: String
    /// Orthographic katakana reading (キョウ), distinct from the phonetic `pron` (キョー).
    public var read: String
    public var pos: String
    public var acc: Int
    public var moraSize: Int
    public var chainFlag: Int
}

public final class OJTFrontend {
    private let handle: OpaquePointer

    /// Load the UTF-8 Open JTalk dictionary at `dictionaryDirectory`.
    /// - Returns: `nil` if the dictionary is missing or fails to load.
    public init?(dictionaryDirectory: URL) {
        guard let handle = dictionaryDirectory.path.withCString({ ojt_frontend_create($0) }) else {
            return nil
        }
        self.handle = handle
    }

    deinit {
        ojt_frontend_destroy(handle)
    }

    /// Run the text-processing frontend on `text`, returning its NJD words.
    public func runFrontend(_ text: String) -> [OJTWord] {
        let result = text.withCString { ojt_run_frontend(handle, $0) }
        defer { ojt_result_free(result) }
        guard result.count > 0, let words = result.words else { return [] }

        var out: [OJTWord] = []
        out.reserveCapacity(result.count)
        for index in 0..<result.count {
            let word = words[index]
            out.append(OJTWord(
                surface: String(cString: word.surface),
                base: String(cString: word.base),
                pron: String(cString: word.pron),
                read: String(cString: word.read),
                pos: String(cString: word.pos),
                acc: Int(word.acc),
                moraSize: Int(word.mora_size),
                chainFlag: Int(word.chain_flag)))
        }
        return out
    }
}

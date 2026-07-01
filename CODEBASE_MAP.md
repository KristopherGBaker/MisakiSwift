# CODEBASE_MAP — MisakiSwift (fork, feat/japanese-g2p)

Orientation for changes to the Japanese G2P / furigana-reading path.

## Layout
- `Sources/MisakiSwift/Japanese/OpenJTalkReader.swift` — public furigana-reading surface over
  the OpenJTalk frontend. `hiraganaReading(for:)` → `pron` (phonetic), 
  `orthographicHiraganaReading(for:)` → `read` (orthographic); private `reading(for:keyPath:)`
  joins frontend words and converts katakana→hiragana. `words(for:)` returns per-word
  surface/base/reading.
- `Sources/MisakiSwift/Japanese/OpenJTalkG2P.swift` — phoneme path (`analyze`, `phonemize`);
  shares the same frontend + dictionary.
- `Sources/COpenJTalk/…/njd_set_digit/` — NJD place-value number folding (the 二三 fix lives here).
- `Tests/MisakiSwiftTests/OpenJTalkG2PTests.swift` — reading/G2P tests.

## Conventions
- **Swift Testing only** (`import Testing`, `@Test`, `#expect`, `#require`) — never XCTest.
- Dictionary-integration tests resolve the dict via the existing `dictionaryDirectory()`
  helper and `#require` it, skipping cleanly when `OJT_DICT_DIR` is unset. Existing suites:
  `OpenJTalkPureTests`, `OpenJTalkIntegrationTests` (incl. `nisanIdiom`,
  `genuineNumbersUnchanged`), `HeteronymTests`.
- `OpenJTalkReader` serializes frontend calls with `NSLock` (the C frontend mutates per-call
  state). Kana conversion: `CFStringTransform(_, nil, kCFStringTransformHiraganaKatakana, true)`.
- Pure, dictionary-free logic should be an `internal` function unit-tested via
  `@testable import MisakiSwift` (no dictionary required).
- Minimal, documented diffs; no reformatting of unrelated code; no new dependencies; no
  `Date()`/random in library or tests.

# MisakiSwift — English + Japanese fork

A maintained fork of [mlalma/MisakiSwift](https://github.com/mlalma/MisakiSwift),
the Swift port of the [Misaki](https://github.com/hexgrad/misaki) grapheme-to-phoneme
(G2P) library used by Kokoro TTS. The upstream port covers **English**; this fork
adds a full **Japanese** G2P path (true readings, pitch-accent metadata, and
furigana support) plus a few English accuracy fixes.

It is the G2P backing our [KokoroSwift fork](https://github.com/KristopherGBaker/kokoro-ios)
and Aoede, a local-first reader for macOS and iOS/iPadOS that reads English and
Japanese with furigana.

> **Relationship to upstream.** The English engine — the Misaki pipeline, the
> lexicon, the BART fallback network ported to MLX — is mlalma's port of hexgrad's
> Misaki. This fork exists to carry Japanese support, which upstream isn't taking.
> We develop on the `feat/japanese-g2p` branch, in the open. Original work is
> retained under its Apache-2.0 license (see [LICENSE](LICENSE)).
>
> Notably, the Japanese path uses **no eSpeak** — readings come from Apple's
> frameworks and an optional OpenJTalk frontend — so there is no GPL dependency in
> the speech path.

## Supported platforms

- iOS 18.0+ / macOS 15.0+ (other Apple platforms may work)
- Apple Silicon (the English fallback network runs on MLX/Metal)

## Installation

Swift Package Manager — point at this fork's branch:

```swift
dependencies: [
    .package(url: "https://github.com/KristopherGBaker/MisakiSwift", branch: "feat/japanese-g2p")
]
```

## English usage

```swift
import MisakiSwift

let g2p = EnglishG2P(british: false)          // American English
let (phonemes, tokens) = g2p.phonemize(text: "Hello world!")
// "həlˈO wˈɜɹld!"
```

Markdown-style overrides force an exact pronunciation:

```swift
let text = "[Misaki](/misˈɑki/) is a G2P engine designed for [Kokoro](/kˈOkəɹO/) models."
```

## Japanese usage

Two engines implement the shared `JapanesePhonemizer` interface
(`phonemize(text:) -> (String, [MToken])`):

- **`OpenJTalkG2P`** — drives a vendored Open JTalk frontend (`COpenJTalk`) for true
  morphological readings (私→ワタシ, contextual は→ワ, counters like 3日→ミッカ) and
  **phonemic pitch accent** (箸 vs 橋). Preferred when its dictionary is available.
- **`JapaneseG2P`** — a pure-Apple fallback (`CFStringTokenizer` + ICU transforms),
  no native dependency, used when no Open JTalk dictionary is installed.

Both emit IPA from the model-faithful `KanaToIPA` table (cutlet Hepburn), so every
phoneme is in Kokoro's vocabulary.

```swift
import MisakiSwift

// Point at an Open JTalk UTF-8 dictionary directory for the OpenJTalk path;
// leave nil to use the pure-Apple fallback.
JapaneseG2PConfiguration.dictionaryDirectory = openJTalkDictionaryURL

let g2p = makeJapanesePhonemizer()            // resolves to OpenJTalk or the fallback
let (phonemes, tokens) = g2p.phonemize(text: "東京駅はどこですか？")
```

### Furigana / dictionary helpers

`OpenJTalkReader` exposes the analyzer for reading overlays and lookups: per-word
tokenization, the orthographic katakana reading (for furigana), and the NJD
dictionary base form (食べました→食べる) for dictionary lookup. These let a UI render
a furigana ruby that matches the spoken reading.

## English accuracy fixes in this fork

- **Context-aware tense disambiguation** for common heteronyms — e.g. past-tense
  "read", "reread", and "wound" are read correctly from sentence context.

## Architecture

- **`EnglishG2P`** — tokenization → lexicon lookup → BART (MLX) fallback for OOV words
- **`Lexicon`** — gold/silver pronunciation dictionaries
- **`EnglishFallbackNetwork`** — transformer phoneme predictor (US/GB) on MLX
- **`OpenJTalkG2P` / `JapaneseG2P`** — Japanese G2P engines (this fork)
- **`COpenJTalk`** — vendored Open JTalk text-processing frontend (C target)

## Key differences from Python Misaki

1. **POS tagging** uses Apple's `NaturalLanguage` framework instead of SpaCy.
2. **Neural fallback** is a BART model ported to [MLX](https://github.com/ml-explore/mlx-swift).
3. **Japanese** is OpenJTalk + Apple frameworks (no eSpeak, no GPL); pitch accent is
   computed as metadata (downstep injection is gated off by default).
4. **Resources** (model weights, dictionaries) are bundled in the Swift package.

## Dependencies

- [MLX Swift](https://github.com/ml-explore/mlx-swift) — pinned `exact: "0.31.4"`
- **NaturalLanguage** — Apple's built-in POS tagging / tokenization
- [MLXUtilsLibrary](https://github.com/mlalma/MLXUtilsLibrary) — `MToken`
- **COpenJTalk** — vendored Open JTalk frontend (bundled C target, this fork)

## Credits

- **Misaki G2P** — [hexgrad](https://github.com/hexgrad/misaki)
- **Swift port (MisakiSwift)** — [Lassi Maksimainen (mlalma)](https://github.com/mlalma/MisakiSwift)
- **Japanese support + this fork** — [Kristopher Baker](https://github.com/KristopherGBaker)
- Japanese reading/accent logic follows [cutlet](https://github.com/polm/cutlet) and
  Misaki's `ja` path; Open JTalk by the Nagoya Institute of Technology.

## License

Apache-2.0 — see [LICENSE](LICENSE). Fork modifications © 2025–2026 Kristopher
Baker, released under the same license. The vendored Open JTalk frontend retains
its own (modified BSD) license terms.

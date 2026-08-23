// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "MisakiSwift",
  platforms: [
    .iOS(.v18), .macOS(.v15)
  ],
  products: [
    .library(
      name: "MisakiSwift",
      type: .dynamic,
      targets: ["MisakiSwift"]
    ),
    // The Open JTalk reading path with no MLX and no CoreFoundation, so it cross-compiles
    // for Android. `MisakiSwift` re-exports it, so existing consumers see no change.
    .library(
      name: "MisakiJapanese",
      targets: ["MisakiJapanese"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
    // Our fork of 0.0.6, whose ONLY change is repointing its ZIPFoundation at the Kits fork.
    //
    // SwiftPM keys package identity on the URL's last path component, so upstream
    // `weichsel/ZIPFoundation` and that fork are ONE package to it. Upstream MLXUtilsLibrary
    // depends on upstream ZIPFoundation, so any consumer whose graph also reaches the Kits
    // fork gets two locations for one identity and a pin that cannot be checked out
    // ("Couldn't check out revision ..."). Pointing at the fork HERE means consumers do not
    // have to know: taking the MLX-free `MisakiJapanese` product previously still dragged
    // this whole graph in and broke on exactly that.
    .package(url: "https://github.com/KristopherGBaker/MLXUtilsLibrary", branch: "kits-android")
  ],
  targets: [
    // Vendored Open JTalk text-processing frontend (modified-BSD, NOT GPL). Exposes
    // a thin C API (`copenjtalk.h`) over the morphological + accent analysis pipeline;
    // synthesis (hts_engine) is intentionally omitted — Kokoro produces the audio.
    .target(
      name: "COpenJTalk",
      exclude: [
        "openjtalk/COPYING",
        "openjtalk/mecab/COPYING",
        // CLI dictionary-compiler tool (defines its own `main`); never called at
        // runtime — Aoede ships the prebuilt UTF-8 dictionary.
        "openjtalk/mecab/mecab-dict-index.cpp"
      ],
      cSettings: [
        .headerSearchPath("openjtalk/jpcommon"),
        .headerSearchPath("openjtalk/mecab"),
        .headerSearchPath("openjtalk/mecab2njd"),
        .headerSearchPath("openjtalk/njd"),
        .headerSearchPath("openjtalk/njd2jpcommon"),
        .headerSearchPath("openjtalk/njd_set_accent_phrase"),
        .headerSearchPath("openjtalk/njd_set_accent_type"),
        .headerSearchPath("openjtalk/njd_set_digit"),
        .headerSearchPath("openjtalk/njd_set_long_vowel"),
        .headerSearchPath("openjtalk/njd_set_pronunciation"),
        .headerSearchPath("openjtalk/njd_set_unvoiced_vowel"),
        .headerSearchPath("openjtalk/text2mecab"),
        .define("HAVE_CONFIG_H"),
        .define("DIC_VERSION", to: "102"),
        .define("MECAB_DEFAULT_RC", to: "\"dummy\""),
        .define("CHARSET_UTF_8"),
        .define("MECAB_CHARSET", to: "utf-8"),
        .define("VERSION", to: "\"1.11\"")
      ],
      cxxSettings: [
        .headerSearchPath("openjtalk/jpcommon"),
        .headerSearchPath("openjtalk/mecab"),
        .headerSearchPath("openjtalk/mecab2njd"),
        .headerSearchPath("openjtalk/njd"),
        .headerSearchPath("openjtalk/njd2jpcommon"),
        .headerSearchPath("openjtalk/njd_set_accent_phrase"),
        .headerSearchPath("openjtalk/njd_set_accent_type"),
        .headerSearchPath("openjtalk/njd_set_digit"),
        .headerSearchPath("openjtalk/njd_set_long_vowel"),
        .headerSearchPath("openjtalk/njd_set_pronunciation"),
        .headerSearchPath("openjtalk/njd_set_unvoiced_vowel"),
        .headerSearchPath("openjtalk/text2mecab"),
        .define("HAVE_CONFIG_H"),
        .define("DIC_VERSION", to: "102"),
        .define("MECAB_DEFAULT_RC", to: "\"dummy\""),
        .define("CHARSET_UTF_8"),
        .define("MECAB_CHARSET", to: "utf-8"),
        .define("VERSION", to: "\"1.11\"")
      ]
    ),
    // Portable half: Open JTalk morphology and readings. Foundation + COpenJTalk only.
    // Everything MLX-shaped, and the CoreFoundation G2P fallback, stay in MisakiSwift.
    .target(
      name: "MisakiJapanese",
      dependencies: ["COpenJTalk"]
    ),
    .target(
      name: "MisakiSwift",
      dependencies: [
        "COpenJTalk",
        "MisakiJapanese",
        .product(name: "MLX", package: "mlx-swift"),
        .product(name: "MLXNN", package: "mlx-swift"),
        .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary")
     ],
     resources: [
      .copy("../../Resources/")
     ]
    ),
    .testTarget(
      name: "MisakiJapaneseTests",
      dependencies: ["MisakiJapanese"]
    ),
    .testTarget(
      name: "MisakiSwiftTests",
      dependencies: ["MisakiSwift", "MisakiJapanese"]
    ),
  ]
)

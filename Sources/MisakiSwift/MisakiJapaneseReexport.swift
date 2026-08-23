// The Open JTalk reading path moved to the `MisakiJapanese` module so it can build without
// MLX (and therefore for Android). Re-exported here so every existing consumer of
// `import MisakiSwift` keeps seeing `OpenJTalkReader`, `OpenJTalkWord` and
// `JapaneseG2PConfiguration` exactly as before: this split is meant to be invisible to them.
@_exported import MisakiJapanese

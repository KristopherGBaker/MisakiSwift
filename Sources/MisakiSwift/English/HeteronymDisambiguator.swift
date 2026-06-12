import NaturalLanguage
import MLXUtilsLibrary

/// Context rules that recover English verb *tense* for the handful of heteronyms whose
/// pronunciation is keyed on fine-grained Penn tags (VBD/VBN/VBP) in the gold lexicon —
/// distinctions Apple's `NLTagger` cannot make because `.lexicalClass` only yields a
/// coarse `.verb`. Upstream Misaki gets these for free from spaCy's contextual tagger;
/// this re-derives the load-bearing past-vs-present signal from the local token
/// neighbourhood so "I read it yesterday" (ɹˈɛd) no longer collapses to the present
/// "I read every day" (ɹˈid).
extension EnglishG2P {
  /// Lowercased words whose lexicon entry is keyed on verb tense. "used" is intentionally
  /// excluded — `Lexicon.getSpecialCase` already special-cases "used (to)".
  static let tenseHeteronyms: Set<String> = ["read", "reread", "wound"]

  private static let beForms: Set<String> = ["be", "been", "being", "is", "am", "are", "was", "were"]
  private static let haveForms: Set<String> = ["have", "has", "had", "having"]
  private static let modals: Set<String> = [
    "will", "would", "shall", "should", "can", "could", "may", "might", "must", "do", "does", "did", "let"
  ]
  private static let pastCues: Set<String> = [
    "yesterday", "ago", "earlier", "recently", "previously", "once", "already", "then"
  ]
  /// Adverbs / negation skipped when scanning left for a governing auxiliary
  /// (e.g. "have *already* read", "was *widely* read").
  private static let leftSkippable: Set<String> = ["not", "never", "also", "just", "still", "again", "really", "actually"]

  /// Returns the fine-grained Penn tag ("VBN"/"VBD"/"VB") when local context disambiguates
  /// the tense of the tense-heteronym at `index`, or `nil` to leave the lexicon DEFAULT
  /// (present-tense / noun) reading in place.
  static func tenseTag(for tokens: [MToken], at index: Int) -> String? {
    let word = tokens[index].text.lowercased()

    // 1. Nearest governing auxiliary / modal / infinitival "to", skipping adverbs.
    var j = index - 1
    var hops = 0
    while j >= 0, hops < 4 {
      let neighbour = tokens[j]
      let w = neighbour.text.lowercased()
      if haveForms.contains(w) || beForms.contains(w) { return "VBN" }   // "have/was read"
      if modals.contains(w) { return "VB" }                             // "will/did read"
      if w == "to", neighbour.tag == .particle || neighbour.tag == .preposition { return "VB" } // "to read"
      if leftSkippable.contains(w) || neighbour.tag == .adverb { j -= 1; hops += 1; continue }
      break  // a content word that isn't an auxiliary — stop scanning
    }

    // 2. "wound" as a verb is always the past of "wind" (the present is spelled "wind"),
    //    so a verb reading alone is enough to choose the VBD pronunciation.
    if word == "wound", tokens[index].tag == .verb { return "VBD" }

    // 3. Otherwise rely on an explicit past-time cue, but only when this token actually
    //    reads as a verb — avoids "a good read yesterday" (noun) misfiring.
    if tokens[index].tag == .verb {
      let lo = max(0, index - 4), hi = min(tokens.count - 1, index + 4)
      for k in lo...hi where k != index {
        if pastCues.contains(tokens[k].text.lowercased()) { return "VBD" }  // "read it yesterday"
      }
    }
    return nil
  }
}

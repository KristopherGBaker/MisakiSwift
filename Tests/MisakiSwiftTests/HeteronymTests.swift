import Testing
@testable import MisakiSwift

/// American English phonemes for the "read" heteronym in the gold lexicon:
///   present / base (DEFAULT) → "ɹˈid"  ("reed")
///   past tense / participle  → "ɹˈɛd"  ("red")
private let reed = "ɹˈid"
private let red = "ɹˈɛd"

// MARK: - "read": past tense / past participle should be "red"

@Test func heteronym_read_pastParticiple_haveAux_isRed() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "I have read that book.")
  #expect(result.contains(red))
  #expect(!result.contains(reed))
}

@Test func heteronym_read_pastParticiple_beAux_isRed() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "It was read by everyone.")
  #expect(result.contains(red))
}

@Test func heteronym_read_simplePast_temporalCue_isRed() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "I read the newspaper yesterday.")
  #expect(result.contains(red))
}

// MARK: - "read": present / infinitive should stay "reed"

@Test func heteronym_read_infinitive_isReed() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "I want to read it.")
  #expect(result.contains(reed))
  #expect(!result.contains(red))
}

@Test func heteronym_read_presentHabitual_isReed() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "I read every single day.")
  #expect(result.contains(reed))
  #expect(!result.contains(red))
}

@Test func heteronym_read_modal_isReed() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "She will read it tomorrow.")
  #expect(result.contains(reed))
}

// MARK: - "wound": verb (past of wind) vs noun

@Test func heteronym_wound_noun_isWuund() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "She suffered a terrible wound.")
  #expect(result.contains("wˈund"))   // noun → DEFAULT
}

@Test func heteronym_wound_verb_isWownd() async throws {
  let g2p = EnglishG2P(british: false)
  let (result, _) = g2p.phonemize(text: "He wound the clock yesterday.")
  #expect(result.contains("wˈWnd"))   // verb (past of wind) → VBD
}

// MARK: - regression: coarse noun/verb heteronyms still resolve via the parent tag

@Test func heteronym_record_nounVsVerb_unaffected() async throws {
  let g2p = EnglishG2P(british: false)
  let noun = g2p.phonemize(text: "I played the record.").0
  let verb = g2p.phonemize(text: "Please record the meeting.").0
  #expect(noun.contains("ɹˈɛkəɹd"))   // NOUN
  #expect(verb.contains("ɹəkˈɔɹd"))   // VERB
}

import Testing

@testable import TranStudy

struct ExampleSentenceVocabularyMatcherTests {
  @Test("matches an inflected verb by its dictionary form")
  func matchesInflectedVerb() {
    let sentence = "She fumbled the ball."

    let matches = ExampleSentenceVocabularyMatcher.matchingRanges(
      in: sentence,
      vocabulary: "fumble"
    )

    #expect(matches.map { String(sentence[$0]) } == ["fumbled"])
  }

  @Test("matches an irregular verb by its dictionary form")
  func matchesIrregularVerb() {
    let sentence = "She ran home."

    let matches = ExampleSentenceVocabularyMatcher.matchingRanges(
      in: sentence,
      vocabulary: "run"
    )

    #expect(matches.map { String(sentence[$0]) } == ["ran"])
  }

  @Test("does not highlight a different word with the same prefix")
  func doesNotMatchDifferentWordWithSamePrefix() {
    let sentence = "The fumbler fumbled the ball."

    let matches = ExampleSentenceVocabularyMatcher.matchingRanges(
      in: sentence,
      vocabulary: "fumble"
    )

    #expect(matches.map { String(sentence[$0]) } == ["fumbled"])
  }

  @Test("keeps phrase matching literal")
  func matchesPhraseLiterally() {
    let sentence = "She succeeded in spite of the setbacks."

    let matches = ExampleSentenceVocabularyMatcher.matchingRanges(
      in: sentence,
      vocabulary: "in spite of"
    )

    #expect(matches.map { String(sentence[$0]) } == ["in spite of"])
  }
}

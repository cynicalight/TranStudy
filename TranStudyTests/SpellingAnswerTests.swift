import Testing

@testable import TranStudy

struct SpellingAnswerTests {
  @Test("spelling accepts case and surrounding whitespace differences")
  func matchesCaseAndWhitespaceDifferences() {
    #expect(SpellingAnswer.matches("  Resilient  ", expected: "resilient"))
    #expect(SpellingAnswer.matches("in   spite\nof", expected: "in spite of"))
    #expect(SpellingAnswer.matches("inspiteof", expected: "in spite of"))
  }

  @Test("spelling rejects a different answer")
  func rejectsDifferentAnswer() {
    #expect(!SpellingAnswer.matches("resilience", expected: "resilient"))
  }
}

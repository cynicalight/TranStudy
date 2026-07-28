import Foundation
import Testing

@testable import TranStudy

struct SelectionSentenceContextTests {
  @Test("selected text resolves its target sentence and immediate neighbors")
  func selectedTextResolvesSurroundingSentences() {
    let document = "It was getting late. She ran home. Her mother smiled."
    let selectedRange = (document as NSString).range(of: "ran")

    let context = SelectionSentenceContext.extract(
      from: document,
      selectedRange: CFRange(
        location: selectedRange.location,
        length: selectedRange.length
      )
    )

    #expect(
      context
        == SelectionSentenceContext(
          targetSentence: "She ran home.",
          previousSentence: "It was getting late.",
          nextSentence: "Her mother smiled."
        ))
  }

  @Test("missing document context rejects an incomplete snapshot")
  func missingDocumentContextRejectsIncompleteSnapshot() {
    let context = SelectionSentenceContext.extract(
      from: "Short text.",
      selectedRange: CFRange(location: 100, length: 3)
    )

    #expect(context == nil)
  }
}

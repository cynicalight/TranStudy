import Foundation
import Testing

@testable import TranStudy

struct SelectionSentenceContextTests {
  @Test("selection-only word capture preserves the sentence fallback")
  @MainActor
  func selectionOnlyWordCapturePreservesSentenceFallback() throws {
    let sentenceContext = SelectionSentenceContext(
      targetSentence: "You can use it where you work.",
      previousSentence: nil,
      nextSentence: nil
    )
    let capture = try #require(
      AccessibilitySelectionProvider.SelectionContextCapture(
        sentenceContext: sentenceContext,
        wordContext: SelectionWordContext(
          precedingText: "",
          selectedText: "where",
          followingText: ""
        )
      ))

    #expect(capture.sentenceContext == sentenceContext)
    #expect(capture.wordContext == nil)
    #expect(capture.diagnosticContextText == sentenceContext.targetSentence)
  }

  @Test("selection-only word capture without a sentence is unavailable")
  @MainActor
  func selectionOnlyWordCaptureWithoutSentenceIsUnavailable() {
    let capture = AccessibilitySelectionProvider.SelectionContextCapture(
      sentenceContext: nil,
      wordContext: SelectionWordContext(
        precedingText: "",
        selectedText: "where",
        followingText: ""
      )
    )

    #expect(capture == nil)
  }

  @Test("selection-only word context is not a surrounding word window")
  func selectionOnlyWordContextIsNotUsable() {
    let context = SelectionWordContext(
      precedingText: " \n",
      selectedText: "where",
      followingText: "\t"
    )

    #expect(!context.hasSurroundingContent)
  }

  @Test("one populated side keeps a boundary word context usable")
  func onePopulatedSideKeepsWordContextUsable() {
    let documentStart = SelectionWordContext(
      precedingText: "",
      selectedText: "First",
      followingText: " word after"
    )
    let documentEnd = SelectionWordContext(
      precedingText: "word before ",
      selectedText: "last",
      followingText: ""
    )

    #expect(documentStart.hasSurroundingContent)
    #expect(documentEnd.hasSurroundingContent)
  }

  @Test("word context keeps exactly fifty words on each side of the selection")
  func wordContextKeepsFiftyWordsOnEachSide() throws {
    let precedingWords = (1...60).map { "before\($0)" }
    let followingWords = (1...60).map { "after\($0)" }
    let document = (precedingWords + ["selected"] + followingWords).joined(separator: " ")
    let selectedRange = (document as NSString).range(of: "selected")

    let context = try #require(
      SelectionWordContext.extract(
        from: document,
        selectedRange: CFRange(
          location: selectedRange.location,
          length: selectedRange.length
        )
      ))

    #expect(context.precedingText.split(whereSeparator: \.isWhitespace).count == 50)
    #expect(context.precedingText.hasPrefix("before11"))
    #expect(context.followingText.split(whereSeparator: \.isWhitespace).count == 50)
    #expect(context.followingText.hasSuffix("after50 "))
    #expect(context.combinedText.contains("before60 selected after1"))
  }

  @Test("word context preserves punctuation and formatting boundaries around the selection")
  func wordContextPreservesOriginalBoundaries() throws {
    let document = "The novel called The Left Hand of Darkness changed science fiction forever."
    let selectedRange = (document as NSString).range(of: "Left")

    let context = try #require(
      SelectionWordContext.extract(
        from: document,
        selectedRange: CFRange(
          location: selectedRange.location,
          length: selectedRange.length
        )
      ))

    #expect(context.precedingText == "The novel called The ")
    #expect(context.selectedText == "Left")
    #expect(context.followingText == " Hand of Darkness changed science fiction forever.")
    #expect(context.combinedText == document)
  }

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

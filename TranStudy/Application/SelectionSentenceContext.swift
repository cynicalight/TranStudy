import Foundation

struct SelectionSentenceContext: Equatable {
  let targetSentence: String
  let previousSentence: String?
  let nextSentence: String?

  static func extract(
    from documentText: String,
    selectedRange: CFRange
  ) -> SelectionSentenceContext? {
    let nsDocument = documentText as NSString
    let sentenceDocument =
      documentText
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
    guard
      selectedRange.location >= 0,
      selectedRange.location <= nsDocument.length,
      selectedRange.length >= 0,
      selectedRange.length <= nsDocument.length - selectedRange.location
    else {
      return nil
    }

    var sentences: [(text: String, range: NSRange)] = []
    sentenceDocument.enumerateSubstrings(
      in: sentenceDocument.startIndex..<sentenceDocument.endIndex,
      options: [.bySentences, .substringNotRequired]
    ) { _, substringRange, _, _ in
      let range = NSRange(substringRange, in: sentenceDocument)
      let text = TranslationTextNormalizer.collapseWhitespace(
        in: nsDocument.substring(with: range)
      )
      if !text.isEmpty {
        sentences.append((text, range))
      }
    }

    let selectionLocation =
      selectedRange.location == nsDocument.length
      ? max(0, selectedRange.location - 1)
      : selectedRange.location
    guard
      let targetIndex = sentences.firstIndex(where: { sentence in
        NSLocationInRange(selectionLocation, sentence.range)
      }),
      selectedRange.location >= sentences[targetIndex].range.location,
      selectedRange.location + selectedRange.length
        <= NSMaxRange(sentences[targetIndex].range)
    else {
      return nil
    }

    return SelectionSentenceContext(
      targetSentence: sentences[targetIndex].text,
      previousSentence: targetIndex > 0 ? sentences[targetIndex - 1].text : nil,
      nextSentence:
        targetIndex + 1 < sentences.count
        ? sentences[targetIndex + 1].text
        : nil
    )
  }
}

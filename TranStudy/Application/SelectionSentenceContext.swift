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
    guard
      selectedRange.location >= 0,
      selectedRange.location <= nsDocument.length,
      selectedRange.length >= 0,
      selectedRange.length <= nsDocument.length - selectedRange.location
    else {
      return nil
    }

    var sentences: [(text: String, range: NSRange, lineRange: NSRange)] = []
    documentText.enumerateSubstrings(
      in: documentText.startIndex..<documentText.endIndex,
      options: [.byLines, .substringNotRequired]
    ) { _, lineSubstringRange, _, _ in
      let lineRange = NSRange(lineSubstringRange, in: documentText)
      documentText.enumerateSubstrings(
        in: lineSubstringRange,
        options: [.bySentences, .substringNotRequired]
      ) { _, sentenceSubstringRange, _, _ in
        let sentenceRange = NSRange(sentenceSubstringRange, in: documentText)
        let text = TranslationTextNormalizer.collapseWhitespace(
          in: nsDocument.substring(with: sentenceRange)
        )
        if !text.isEmpty {
          sentences.append((text, sentenceRange, lineRange))
        }
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

    let targetSentence = sentences[targetIndex]
    let previousSentence: String? =
      if targetIndex > 0,
        sentences[targetIndex - 1].lineRange == targetSentence.lineRange
      {
        sentences[targetIndex - 1].text
      } else {
        nil
      }
    let nextSentence: String? =
      if targetIndex + 1 < sentences.count,
        sentences[targetIndex + 1].lineRange == targetSentence.lineRange
      {
        sentences[targetIndex + 1].text
      } else {
        nil
      }
    return SelectionSentenceContext(
      targetSentence: TranslationTextNormalizer.cleanExampleSentenceBoundaries(
        in: targetSentence.text
      ),
      previousSentence: previousSentence,
      nextSentence: nextSentence
    )
  }
}

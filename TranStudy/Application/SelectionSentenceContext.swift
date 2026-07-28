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
      selectedRange.location <= nsDocument.length
    else {
      return nil
    }

    var sentences: [(text: String, range: NSRange)] = []
    documentText.enumerateSubstrings(
      in: documentText.startIndex..<documentText.endIndex,
      options: [.bySentences, .substringNotRequired]
    ) { _, substringRange, _, _ in
      let range = NSRange(substringRange, in: documentText)
      let text = nsDocument.substring(with: range)
        .trimmingCharacters(in: .whitespacesAndNewlines)
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
      })
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

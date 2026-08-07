import Foundation
import NaturalLanguage

enum ExampleSentenceVocabularyMatcher {
  static func matchingRanges(in sentence: String, vocabulary: String) -> [Range<String.Index>] {
    let normalizedVocabulary = vocabulary.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedVocabulary.isEmpty else {
      return []
    }

    var ranges = literalMatchingRanges(in: sentence, vocabulary: normalizedVocabulary)
    guard isSingleEnglishWord(normalizedVocabulary) else {
      return ranges
    }

    let normalizedLemma = normalizedEnglishIdentity(normalizedVocabulary)
    let tagger = NLTagger(tagSchemes: [.lemma])
    tagger.string = sentence
    tagger.enumerateTags(
      in: sentence.startIndex..<sentence.endIndex,
      unit: .word,
      scheme: .lemma,
      options: [.omitPunctuation, .omitWhitespace]
    ) { tag, range in
      guard normalizedEnglishIdentity(tag?.rawValue ?? "") == normalizedLemma else {
        return true
      }
      if !ranges.contains(where: { $0 == range }) {
        ranges.append(range)
      }
      return true
    }

    return ranges.sorted { $0.lowerBound < $1.lowerBound }
  }

  private static func literalMatchingRanges(
    in sentence: String,
    vocabulary: String
  ) -> [Range<String.Index>] {
    let pattern =
      "(?<![\\p{L}\\p{N}])"
      + NSRegularExpression.escapedPattern(for: vocabulary)
      + "(?![\\p{L}\\p{N}])"
    guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    else {
      return []
    }

    let sentenceRange = NSRange(sentence.startIndex..., in: sentence)
    return
      expression
      .matches(in: sentence, range: sentenceRange)
      .compactMap { Range($0.range, in: sentence) }
  }

  private static func isSingleEnglishWord(_ vocabulary: String) -> Bool {
    vocabulary.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil
  }

  private static func normalizedEnglishIdentity(_ text: String) -> String {
    text.lowercased(with: Locale(identifier: "en_US_POSIX"))
  }
}

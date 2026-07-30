import Foundation

enum TranslationTextNormalizer {
  static func collapseWhitespace(in text: String) -> String {
    text
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  static func cleanExampleSentenceBoundaries(in text: String) -> String {
    var cleanedText = collapseWhitespace(in: text)
    while let firstCharacter = cleanedText.first,
      isPunctuationOrSymbol(firstCharacter)
    {
      cleanedText.removeFirst()
      cleanedText = cleanedText.trimmingCharacters(in: .whitespaces)
    }
    while let lastCharacter = cleanedText.last,
      [":", ";", "：", "；"].contains(lastCharacter)
    {
      cleanedText.removeLast()
      cleanedText = cleanedText.trimmingCharacters(in: .whitespaces)
    }
    return cleanedText
  }

  private static func isPunctuationOrSymbol(_ character: Character) -> Bool {
    guard let firstScalar = character.unicodeScalars.first else {
      return false
    }
    return CharacterSet.punctuationCharacters.contains(firstScalar)
      || CharacterSet.symbols.contains(firstScalar)
  }
}

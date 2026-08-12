import Foundation

enum SpellingAnswer {
  static func matches(_ attempt: String, expected: String) -> Bool {
    normalized(attempt) == normalized(expected)
  }

  static func inputCharacters(in text: String) -> [Character] {
    text.filter { !$0.isWhitespace }
  }

  private static func normalized(_ text: String) -> String {
    String(inputCharacters(in: text))
      .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }
}

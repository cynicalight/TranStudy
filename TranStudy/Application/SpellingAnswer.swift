import Foundation

enum SpellingAnswer {
  static func matches(_ attempt: String, expected: String) -> Bool {
    normalized(attempt) == normalized(expected)
  }

  private static func normalized(_ text: String) -> String {
    text
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
  }
}

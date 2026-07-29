import Foundation

enum TranslationTextNormalizer {
  static func collapseWhitespace(in text: String) -> String {
    text
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}

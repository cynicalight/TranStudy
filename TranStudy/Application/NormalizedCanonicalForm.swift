import Foundation

struct NormalizedCanonicalForm: Equatable, Hashable, Sendable {
  let value: String

  init(_ canonicalForm: String) {
    let compatibleText = canonicalForm.precomposedStringWithCompatibilityMapping
    let foldedText = compatibleText.folding(
      options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    value =
      foldedText
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }
}

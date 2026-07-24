struct TranslationRequest: Equatable, Sendable {
  let sourceText: String
}

struct TranslationResult: Equatable, Sendable {
  let sourceText: String
  let translatedText: String
}

enum TranslationError: Error {
  case notConfigured
}

protocol TranslationProviding {
  func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

struct TranslationRequest: Equatable, Sendable {
  let sourceText: String
}

struct TranslationResult: Equatable, Sendable {
  let sourceText: String
  let canonicalForm: String
  let pronunciation: String
  let partOfSpeech: String
  let contextualMeaning: String
  let exampleSentence: String
  let sentenceTranslation: String
}

enum TranslationError: Error {
  case notConfigured
  case invalidResponse
  case serviceUnavailable
}

@MainActor
protocol TranslationProviding {
  func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

enum TranslationRequestKind: Codable, Equatable, Hashable, Sendable {
  case wordOrPhrase
  case contextualSelection
  case longText
}

struct TranslationRequest: Codable, Equatable, Hashable, Sendable {
  let sourceText: String
  let context: String?
  let kind: TranslationRequestKind

  init(
    sourceText: String,
    context: String? = nil,
    kind: TranslationRequestKind = .wordOrPhrase
  ) {
    self.sourceText = sourceText
    self.context = context
    self.kind = kind
  }

  var promptContent: String {
    guard let context, !context.isEmpty else {
      return sourceText
    }

    return """
      Target text:
      \(sourceText)

      Context:
      \(context)
      """
  }
}

struct TranslationResult: Codable, Equatable, Sendable {
  let sourceText: String
  let canonicalForm: String
  let pronunciation: String
  let partOfSpeech: String
  let contextualMeaning: String
  let exampleSentence: String
  let sentenceTranslation: String
}

enum TranslationError: Error, Equatable, Sendable {
  case notConfigured
  case inputTooLong
  case timedOut
  case networkUnavailable
  case invalidResponse
  case serviceUnavailable
}

@MainActor
protocol TranslationProviding {
  func translate(_ request: TranslationRequest) async throws -> TranslationResult
}

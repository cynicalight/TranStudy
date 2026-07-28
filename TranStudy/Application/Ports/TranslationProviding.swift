enum TranslationRequestKind: Codable, Equatable, Hashable, Sendable {
  case wordOrPhrase
  case contextualSelection
  case longText
}

struct TranslationRequest: Codable, Equatable, Hashable, Sendable {
  let sourceText: String
  let context: String?
  let kind: TranslationRequestKind
  let targetSentence: String?

  init(
    sourceText: String,
    context: String? = nil,
    kind: TranslationRequestKind = .wordOrPhrase,
    targetSentence: String? = nil
  ) {
    self.sourceText = sourceText
    self.context = context
    self.kind = kind
    self.targetSentence = targetSentence
  }

  var promptContent: String {
    guard let context, !context.isEmpty else {
      return sourceText
    }

    var content = """
      Target text:
      \(sourceText)

      Context:
      \(context)
      """
    if kind == .contextualSelection, let targetSentence {
      content += """


        Return this exact target sentence unchanged as example_sentence:
        \(targetSentence)
        Translate that exact sentence as sentence_translation. Use adjacent sentences only to
        disambiguate the target text; do not return either adjacent sentence as learning content.
        """
    }
    return content
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

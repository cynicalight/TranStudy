import Foundation

@MainActor
final class OpenAIChatTranslationClient {
  private let provider: TranslationProviderKind
  private let endpoint: URL
  private let model: String
  private let addsDisabledThinking: Bool
  private let apiKeyStore: any APIKeyStoring
  private let httpClient: any HTTPDataLoading

  init(
    provider: TranslationProviderKind,
    endpoint: URL,
    model: String,
    addsDisabledThinking: Bool,
    apiKeyStore: any APIKeyStoring,
    httpClient: any HTTPDataLoading
  ) {
    self.provider = provider
    self.endpoint = endpoint
    self.model = model
    self.addsDisabledThinking = addsDisabledThinking
    self.apiKeyStore = apiKeyStore
    self.httpClient = httpClient
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    guard
      let apiKey = try apiKeyStore.loadAPIKey(for: provider)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    else {
      throw TranslationError.notConfigured
    }

    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = 30
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.httpBody = try JSONEncoder().encode(
      OpenAIChatRequest(
        model: model,
        messages: [
          OpenAIMessage(role: "system", content: Self.systemPrompt),
          OpenAIMessage(role: "user", content: request.promptContent),
        ],
        responseFormat: OpenAIResponseFormat(type: "json_object"),
        thinking: addsDisabledThinking ? OpenAIThinking(type: "disabled") : nil,
        maxTokens: 800
      ))

    let (data, response) = try await httpClient.data(for: urlRequest)
    guard (200..<300).contains(response.statusCode) else {
      throw TranslationError.serviceUnavailable
    }
    guard
      let completion = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
      let content = completion.choices.first?.message.content,
      let contentData = content.data(using: .utf8),
      let payload = try? JSONDecoder().decode(OpenAITranslationPayload.self, from: contentData),
      payload.inputKind == .wordOrPhrase,
      payload.sourceText == request.sourceText,
      !payload.canonicalForm.isEmpty,
      !payload.partOfSpeech.isEmpty,
      !payload.contextualMeaning.isEmpty,
      !payload.exampleSentence.isEmpty,
      !payload.sentenceTranslation.isEmpty
    else {
      throw TranslationError.invalidResponse
    }

    return TranslationResult(
      sourceText: request.sourceText,
      canonicalForm: payload.canonicalForm,
      pronunciation: payload.pronunciation,
      partOfSpeech: payload.partOfSpeech,
      contextualMeaning: payload.contextualMeaning,
      exampleSentence: payload.exampleSentence,
      sentenceTranslation: payload.sentenceTranslation
    )
  }

  private static let systemPrompt = """
    Translate the supplied English word or short phrase into Chinese for a vocabulary learner.
    Return one JSON object only, with exactly these string fields:
    input_kind, source_text, canonical_form, pronunciation, part_of_speech,
    contextual_meaning, example_sentence, sentence_translation.
    Set input_kind to "word_or_phrase" only for a word or short phrase. Set it to
    "long_text" for a sentence or paragraph.
    Preserve the supplied text in source_text. Use an empty pronunciation only when it is
    genuinely unavailable. Do not include markdown or explanations outside the JSON object.
    """
}

struct OpenAIChatRequest: Encodable {
  let model: String
  let messages: [OpenAIMessage]
  let responseFormat: OpenAIResponseFormat
  let thinking: OpenAIThinking?
  let maxTokens: Int

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case responseFormat = "response_format"
    case thinking
    case maxTokens = "max_tokens"
  }
}

struct OpenAIMessage: Codable {
  let role: String
  let content: String
}

struct OpenAIResponseFormat: Encodable {
  let type: String
}

struct OpenAIThinking: Encodable {
  let type: String
}

struct OpenAIChatResponse: Decodable {
  let choices: [OpenAIChoice]
}

struct OpenAIChoice: Decodable {
  let message: OpenAIResponseMessage
}

struct OpenAIResponseMessage: Decodable {
  let content: String?
}

private struct OpenAITranslationPayload: Decodable {
  let inputKind: OpenAITranslationInputKind
  let sourceText: String
  let canonicalForm: String
  let pronunciation: String
  let partOfSpeech: String
  let contextualMeaning: String
  let exampleSentence: String
  let sentenceTranslation: String

  enum CodingKeys: String, CodingKey {
    case inputKind = "input_kind"
    case sourceText = "source_text"
    case canonicalForm = "canonical_form"
    case pronunciation
    case partOfSpeech = "part_of_speech"
    case contextualMeaning = "contextual_meaning"
    case exampleSentence = "example_sentence"
    case sentenceTranslation = "sentence_translation"
  }
}

private enum OpenAITranslationInputKind: String, Decodable {
  case wordOrPhrase = "word_or_phrase"
  case longText = "long_text"
}

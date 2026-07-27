import Foundation

enum DeepSeekModel: String, CaseIterable, Identifiable, Sendable {
  case flash = "deepseek-v4-flash"
  case pro = "deepseek-v4-pro"

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .flash:
      "DeepSeek V4 Flash"
    case .pro:
      "DeepSeek V4 Pro"
    }
  }
}

@MainActor
final class DeepSeekTranslationProvider: TranslationConnectionTesting, TranslationProviding {
  private let apiKeyStore: any APIKeyStoring
  private let httpClient: any HTTPDataLoading
  private let model: DeepSeekModel
  private let endpoint = URL(string: "https://api.deepseek.com/chat/completions")!

  init(
    apiKeyStore: any APIKeyStoring,
    httpClient: any HTTPDataLoading,
    model: DeepSeekModel
  ) {
    self.apiKeyStore = apiKeyStore
    self.httpClient = httpClient
    self.model = model
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    guard
      let apiKey = try apiKeyStore.loadAPIKey()?
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
      ChatRequest(
        model: model.rawValue,
        messages: [
          Message(role: "system", content: Self.systemPrompt),
          Message(role: "user", content: request.sourceText),
        ],
        responseFormat: ResponseFormat(type: "json_object"),
        thinking: Thinking(type: "disabled"),
        maxTokens: 800
      ))

    let (data, response) = try await httpClient.data(for: urlRequest)

    guard (200..<300).contains(response.statusCode) else {
      throw TranslationError.serviceUnavailable
    }

    let completion: ChatResponse
    do {
      completion = try JSONDecoder().decode(ChatResponse.self, from: data)
    } catch {
      throw TranslationError.invalidResponse
    }

    guard
      let content = completion.choices.first?.message.content,
      let contentData = content.data(using: .utf8)
    else {
      throw TranslationError.invalidResponse
    }

    let payload: TranslationPayload
    do {
      payload = try JSONDecoder().decode(TranslationPayload.self, from: contentData)
    } catch {
      throw TranslationError.invalidResponse
    }

    guard
      payload.inputKind == .wordOrPhrase,
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

  func testConnection(apiKey: String) async throws {
    var request = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await httpClient.data(for: request)

    guard (200..<300).contains(response.statusCode) else {
      throw TranslationError.serviceUnavailable
    }

    let modelList: ModelList
    do {
      modelList = try JSONDecoder().decode(ModelList.self, from: data)
    } catch {
      throw TranslationError.invalidResponse
    }

    guard modelList.data.contains(where: { $0.id == model.rawValue }) else {
      throw TranslationError.serviceUnavailable
    }
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

private struct ChatRequest: Encodable {
  let model: String
  let messages: [Message]
  let responseFormat: ResponseFormat
  let thinking: Thinking
  let maxTokens: Int

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case responseFormat = "response_format"
    case thinking
    case maxTokens = "max_tokens"
  }
}

private struct Message: Codable {
  let role: String
  let content: String
}

private struct ResponseFormat: Encodable {
  let type: String
}

private struct Thinking: Encodable {
  let type: String
}

private struct ChatResponse: Decodable {
  let choices: [Choice]
}

private struct Choice: Decodable {
  let message: ResponseMessage
}

private struct ResponseMessage: Decodable {
  let content: String?
}

private struct TranslationPayload: Decodable {
  let inputKind: TranslationInputKind
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

private enum TranslationInputKind: String, Decodable {
  case wordOrPhrase = "word_or_phrase"
  case longText = "long_text"
}

private struct ModelList: Decodable {
  let data: [AvailableModel]
}

private struct AvailableModel: Decodable {
  let id: String
}

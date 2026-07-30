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
    let content = try await completionContent(
      systemPrompt: Self.systemPrompt(for: request.chineseWritingSystem),
      userContent: request.promptContent,
      maxTokens: 800,
      timeoutInterval: 30
    )
    guard
      let contentData = Self.jsonData(from: content),
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

    let exampleAndTranslation =
      if Self.containsHanCharacter(payload.exampleSentence),
        Self.containsLatinLetter(payload.sentenceTranslation)
      {
        (
          exampleSentence: payload.sentenceTranslation,
          sentenceTranslation: payload.exampleSentence
        )
      } else {
        (
          exampleSentence: payload.exampleSentence,
          sentenceTranslation: payload.sentenceTranslation
        )
      }

    guard
      Self.containsLatinLetter(payload.canonicalForm),
      !Self.containsHanCharacter(payload.canonicalForm),
      !Self.containsHanCharacter(payload.pronunciation),
      payload.pronunciation.isEmpty || Self.looksLikeIPA(payload.pronunciation),
      Self.containsHanCharacter(payload.contextualMeaning),
      Self.containsLatinLetter(exampleAndTranslation.exampleSentence),
      Self.containsHanCharacter(exampleAndTranslation.sentenceTranslation),
      request.kind != .contextualSelection
        || request.targetSentence == nil
        || request.targetSentence?.trimmingCharacters(in: .whitespacesAndNewlines)
          == exampleAndTranslation.exampleSentence.trimmingCharacters(
            in: .whitespacesAndNewlines
          )
    else {
      throw TranslationError.invalidResponse
    }

    return TranslationResult(
      sourceText: request.sourceText,
      canonicalForm: payload.canonicalForm,
      pronunciation: payload.pronunciation,
      partOfSpeech: payload.partOfSpeech,
      contextualMeaning: payload.contextualMeaning,
      exampleSentence: exampleAndTranslation.exampleSentence,
      sentenceTranslation: exampleAndTranslation.sentenceTranslation
    )
  }

  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult {
    let content = try await completionContent(
      systemPrompt: Self.longTextSystemPrompt(for: chineseWritingSystem),
      userContent: sourceText,
      maxTokens: 6_000,
      timeoutInterval: 60
    )
    guard
      let contentData = Self.jsonData(from: content),
      let payload = try? JSONDecoder().decode(OpenAILongTextPayload.self, from: contentData),
      payload.inputKind == .longText,
      payload.sourceText == sourceText,
      !payload.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      Self.containsHanCharacter(payload.translation)
    else {
      throw TranslationError.invalidResponse
    }

    return LongTextTranslationResult(
      sourceText: sourceText,
      translatedText: payload.translation
    )
  }

  private func completionContent(
    systemPrompt: String,
    userContent: String,
    maxTokens: Int,
    timeoutInterval: TimeInterval
  ) async throws -> String {
    guard
      let apiKey = try apiKeyStore.loadAPIKey(for: provider)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    else {
      throw TranslationError.notConfigured
    }

    var urlRequest = URLRequest(url: endpoint)
    urlRequest.httpMethod = "POST"
    urlRequest.timeoutInterval = timeoutInterval
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.httpBody = try JSONEncoder().encode(
      OpenAIChatRequest(
        model: model,
        messages: [
          OpenAIMessage(role: "system", content: systemPrompt),
          OpenAIMessage(role: "user", content: userContent),
        ],
        responseFormat: OpenAIResponseFormat(type: "json_object"),
        thinking: addsDisabledThinking ? OpenAIThinking(type: "disabled") : nil,
        maxTokens: maxTokens
      ))

    let (data, response) = try await httpClient.data(for: urlRequest)
    guard (200..<300).contains(response.statusCode) else {
      throw Self.translationError(for: response, responseData: data)
    }
    guard
      let completion = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
      let content = completion.choices.first?.message.content,
      !content.isEmpty
    else {
      throw TranslationError.invalidResponse
    }
    return content
  }

  private static func jsonData(from content: String) -> Data? {
    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedContent.hasPrefix("```") else {
      return trimmedContent.data(using: .utf8)
    }
    guard
      let firstLineBreak = trimmedContent.firstIndex(of: "\n"),
      trimmedContent.hasSuffix("```")
    else {
      return nil
    }

    let fencedJSON = trimmedContent[
      trimmedContent.index(
        after: firstLineBreak)..<trimmedContent.index(
          trimmedContent.endIndex,
          offsetBy: -3
        )
    ]
    return String(fencedJSON)
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .data(using: .utf8)
  }

  private static func translationError(
    for response: HTTPURLResponse,
    responseData: Data
  ) -> TranslationError {
    switch response.statusCode {
    case 400, 404, 405, 422:
      .invalidRequest
    case 401, 403:
      .authenticationFailed
    case 402:
      .quotaExceeded
    case 408, 504:
      .timedOut
    case 413:
      .inputTooLong
    case 429:
      responseIndicatesExhaustedQuota(responseData) ? .quotaExceeded : .rateLimited
    case 500..<600:
      .serviceUnavailable
    default:
      .serviceUnavailable
    }
  }

  private static func responseIndicatesExhaustedQuota(_ data: Data) -> Bool {
    guard let responseText = String(data: data, encoding: .utf8)?.lowercased() else {
      return false
    }

    let quotaMarkers = [
      "insufficient_quota",
      "insufficient balance",
      "insufficient_balance",
      "quota exceeded",
      "credit exhausted",
      "余额不足",
      "额度不足",
    ]
    return quotaMarkers.contains { responseText.contains($0) }
  }

  private static func containsHanCharacter(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      (0x3400...0x4DBF).contains(scalar.value)
        || (0x4E00...0x9FFF).contains(scalar.value)
        || (0xF900...0xFAFF).contains(scalar.value)
    }
  }

  private static func containsLatinLetter(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
      (0x0041...0x005A).contains(scalar.value)
        || (0x0061...0x007A).contains(scalar.value)
    }
  }

  private static func looksLikeIPA(_ text: String) -> Bool {
    let pronunciation = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let isDelimited =
      (pronunciation.hasPrefix("/") && pronunciation.hasSuffix("/"))
      || (pronunciation.hasPrefix("[") && pronunciation.hasSuffix("]"))
    let pinyinToneMarks = CharacterSet(charactersIn: "āáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜü")

    return
      isDelimited
      && pronunciation.rangeOfCharacter(from: .decimalDigits) == nil
      && pronunciation.rangeOfCharacter(from: pinyinToneMarks) == nil
  }

  private static func systemPrompt(for writingSystem: ChineseWritingSystem) -> String {
    """
    Translate the supplied English word or short phrase into Chinese for a vocabulary learner.
    \(writingSystem.promptInstruction)
    Return one JSON object only, with exactly these string fields:
    input_kind, source_text, canonical_form, pronunciation, part_of_speech,
    contextual_meaning, example_sentence, sentence_translation.
    The first non-whitespace character must be `{` and the last must be `}`.
    Never use a Markdown code fence, and do not add prose before or after the JSON object.
    Set input_kind to "word_or_phrase" only for a word or short phrase. Set it to
    "long_text" for a sentence or paragraph.
    Follow these language and meaning requirements exactly:
    - source_text: copy the exact supplied English text unchanged, including its casing,
      punctuation, and whitespace. Never correct or normalize it.
    - canonical_form: its English dictionary lemma, never a Chinese translation.
    - pronunciation: slash-delimited IPA for the exact English source_text form, never
      Mandarin pinyin.
    - part_of_speech: the English part-of-speech name.
    - contextual_meaning: the Chinese meaning of source_text in context.
    - example_sentence: a natural English sentence containing the source word or phrase.
    - sentence_translation: the Chinese translation of example_sentence.
    Use an empty pronunciation only when it is genuinely unavailable. Never reverse English
    source fields and Chinese translation fields. Do not include markdown or explanations
    outside the JSON object.
    """
  }

  private static func longTextSystemPrompt(
    for writingSystem: ChineseWritingSystem
  ) -> String {
    """
    Translate the supplied English sentence or paragraph into natural Chinese.
    \(writingSystem.promptInstruction)
    Preserve paragraph breaks and meaning. Return one JSON object only with exactly these
    string fields: input_kind, source_text, translation.
    The first non-whitespace character must be `{` and the last must be `}`.
    Never use a Markdown code fence, and do not add prose before or after the JSON object.
    Set input_kind to "long_text". Set source_text to the exact supplied English text,
    unchanged. Set translation to the complete Chinese translation. Do not summarize,
    omit content, add commentary, or include markdown outside the JSON object.
    """
  }
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

private struct OpenAILongTextPayload: Decodable {
  let inputKind: OpenAITranslationInputKind
  let sourceText: String
  let translation: String

  enum CodingKeys: String, CodingKey {
    case inputKind = "input_kind"
    case sourceText = "source_text"
    case translation
  }
}

private enum OpenAITranslationInputKind: String, Decodable {
  case wordOrPhrase = "word_or_phrase"
  case longText = "long_text"
}

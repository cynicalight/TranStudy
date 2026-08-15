import Foundation
import Testing

@testable import TranStudy

@MainActor
struct OpenAICompatibleTranslationProviderTests {
  @Test("structured prompt follows the selected Chinese writing system")
  func structuredPromptUsesSelectedChineseWritingSystem() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "resilient",
        "canonical_form": "resilient",
        "pronunciation": "/rɪˈzɪliənt/",
        "part_of_speech": "adjective",
        "contextual_meaning": "有韌性的",
        "example_sentence": "The team remained resilient.",
        "sentence_translation": "團隊依然保持韌性。",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: responseContent, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let httpClient = CustomProviderTestHTTPClient(
      data: responseBody,
      statusCode: 200
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: httpClient
    )

    _ = try await provider.translate(
      TranslationRequest(
        sourceText: "resilient",
        chineseWritingSystem: .traditional
      )
    )

    let request = try #require(httpClient.lastRequest)
    let bodyData = try #require(request.httpBody)
    let body = try #require(
      JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    )
    let messages = try #require(body["messages"] as? [[String: String]])
    let systemPrompt = try #require(messages.first?["content"])
    #expect(
      systemPrompt.contains("Use Traditional Chinese characters for every Chinese output field."))
    #expect(systemPrompt.contains("first non-whitespace character must be `{`"))
    #expect(systemPrompt.contains("Never use a Markdown code fence"))
    #expect(messages.map { $0["role"] } == ["system", "user", "assistant", "user"])
    #expect(messages[1]["content"] == "resilient")
    #expect(messages[2]["content"]?.contains("\"source_text\":\"resilient\"") == true)
    #expect(messages[2]["content"]?.contains("\"pronunciation\":\"/rɪˈzɪliənt/\"") == true)
  }

  @Test("custom provider uses its configured endpoint model and API key")
  func customProviderUsesConfiguredRequest() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "ran",
        "canonical_form": "run",
        "pronunciation": "/ræn/",
        "part_of_speech": "verb",
        "contextual_meaning": "奔跑",
        "example_sentence": "She ran home.",
        "sentence_translation": "她跑回了家。",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: responseContent, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let httpClient = CustomProviderTestHTTPClient(
      data: responseBody,
      statusCode: 200
    )
    let configuration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "https://example.com/v1",
      customModel: "example-model"
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: configuration,
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: httpClient
    )
    let homeContext = SelectionWordContext(
      precedingText: "She ",
      selectedText: "ran",
      followingText: " home."
    )

    let result = try await provider.translate(
      TranslationRequest(
        sourceText: "ran",
        context: [
          "Text before the selected occurrence (up to 50 words):\nShe ",
          "Selected occurrence:\nran",
          "Text after the selected occurrence (up to 50 words):\n home.",
        ].joined(separator: "\n\n"),
        kind: .contextualSelection,
        targetSentence: "ran",
        selectionWordContext: homeContext
      )
    )

    let request = try #require(httpClient.lastRequest)
    #expect(request.url?.absoluteString == "https://example.com/v1/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer custom-api-key")
    let bodyData = try #require(request.httpBody)
    let body = try #require(
      JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    )
    #expect(body["model"] as? String == "example-model")
    let messages = try #require(body["messages"] as? [[String: String]])
    let systemPrompt = try #require(messages.first?["content"])
    let userMessage = try #require(messages.last?["content"])
    #expect(userMessage.contains("Text before the selected occurrence (up to 50 words):\nShe "))
    #expect(userMessage.contains("Selected occurrence:\nran"))
    #expect(userMessage.contains("Text after the selected occurrence (up to 50 words):\n home."))
    #expect(userMessage.contains("Extract the complete original sentence"))
    #expect(userMessage.contains("only a potentially incomplete hint:\nran"))
    #expect(userMessage.contains("Formatting boundaries"))
    #expect(!userMessage.contains("Return this exact target sentence unchanged"))
    #expect(systemPrompt.contains("copy the complete original sentence"))
    #expect(result.canonicalForm == "run")

    let correctedContextResult = try await provider.translate(
      TranslationRequest(
        sourceText: "ran",
        context: "She  ran home.",
        kind: .contextualSelection,
        selectionWordContext: SelectionWordContext(
          precedingText: "She  ",
          selectedText: "ran",
          followingText: " home."
        )
      ))
    #expect(correctedContextResult.exampleSentence == "She ran home.")
    #expect(correctedContextResult.sentenceTranslation == "她跑回了家。")

    do {
      try await provider.translate(
        TranslationRequest(
          sourceText: "ran",
          context: "They ran away.",
          kind: .contextualSelection,
          selectionWordContext: SelectionWordContext(
            precedingText: "They ",
            selectedText: "ran",
            followingText: " away."
          )
        ))
      Issue.record("Expected mismatched selection context to fail")
    } catch let error as TranslationError {
      #expect(
        error
          == .invalidResponse(
            .invalidEnglishContent,
            diagnosticReason: .exampleSentenceDoesNotMatchSelectionContext,
            httpStatusCode: 200
          )
      )
    }
  }

  @Test("recoverable source spelling drift does not replace the requested text")
  func responseSourceSpellingDriftUsesRequestedText() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "cliché",
        "canonical_form": "cliché",
        "pronunciation": "/kliːˈʃeɪ/",
        "part_of_speech": "noun",
        "contextual_meaning": "陈词滥调",
        "example_sentence": "The ending felt like a cliche.",
        "sentence_translation": "这个结局感觉像是陈词滥调。",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: responseContent, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let configuration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "https://example.com/v1",
      customModel: "example-model"
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: configuration,
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: CustomProviderTestHTTPClient(data: responseBody, statusCode: 206)
    )

    let result = try await provider.translate(TranslationRequest(sourceText: "cliche"))

    #expect(result.sourceText == "cliche")
    #expect(result.canonicalForm == "cliché")

    await #expect(
      throws: TranslationError.invalidResponse(
        .invalidEnglishContent,
        diagnosticReason: .responseSourceTextMismatch,
        httpStatusCode: 206
      )
    ) {
      try await provider.translate(TranslationRequest(sourceText: "different text"))
    }
  }

  @Test("reversed English example and Chinese translation are corrected")
  func reversedExampleAndTranslationAreCorrected() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "ran",
        "canonical_form": "run",
        "pronunciation": "/ræn/",
        "part_of_speech": "verb",
        "contextual_meaning": "奔跑",
        "example_sentence": "她跑回了家。",
        "sentence_translation": "She ran home.",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: responseContent, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: CustomProviderTestHTTPClient(data: responseBody, statusCode: 200)
    )

    let result = try await provider.translate(TranslationRequest(sourceText: "ran"))

    #expect(result.exampleSentence == "She ran home.")
    #expect(result.sentenceTranslation == "她跑回了家。")
  }

  @Test("code-fenced JSON response is accepted")
  func codeFencedJSONResponseIsAccepted() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "ran",
        "canonical_form": "run",
        "pronunciation": "/ræn/",
        "part_of_speech": "verb",
        "contextual_meaning": "奔跑",
        "example_sentence": "She ran home.",
        "sentence_translation": "她跑回了家。",
      ],
      options: [.sortedKeys]
    )
    let fencedContent =
      "```json\n\(try #require(String(data: responseContent, encoding: .utf8)))\n```"
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": fencedContent
            ]
          ]
        ]
      ]
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: CustomProviderTestHTTPClient(data: responseBody, statusCode: 200)
    )

    let result = try await provider.translate(TranslationRequest(sourceText: "ran"))

    #expect(result.canonicalForm == "run")
  }

  @Test("malformed JSON response is retried once with the original response attached")
  func malformedJSONResponseIsRetriedOnce() async throws {
    let repairedContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "ran",
        "canonical_form": "run",
        "pronunciation": "/ræn/",
        "part_of_speech": "verb",
        "contextual_meaning": "奔跑",
        "example_sentence": "She ran home.",
        "sentence_translation": "她跑回了家。",
      ]
    )
    let initialResponse = try completionResponse(content: "{ this is not valid JSON")
    let repairedResponse = try completionResponse(
      content: try #require(String(data: repairedContent, encoding: .utf8))
    )
    let httpClient = SequencedCustomProviderTestHTTPClient(
      responses: [
        (data: initialResponse, statusCode: 200),
        (data: repairedResponse, statusCode: 200),
      ]
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: httpClient
    )

    let result = try await provider.translate(TranslationRequest(sourceText: "ran"))

    #expect(result.canonicalForm == "run")
    #expect(httpClient.requests.count == 2)
    let retryBodyData = try #require(httpClient.requests.last?.httpBody)
    let retryBody = try #require(
      JSONSerialization.jsonObject(with: retryBodyData) as? [String: Any]
    )
    let retryMessages = try #require(retryBody["messages"] as? [[String: String]])
    let retryContent = try #require(retryMessages.last?["content"])
    #expect(retryContent.contains("\"original_request\":\"ran\""))
    #expect(retryContent.contains("\"malformed_response\":\"{ this is not valid JSON\""))
  }

  @Test("a second malformed JSON response is not retried again")
  func secondMalformedJSONResponseIsNotRetriedAgain() async throws {
    let malformedResponse = try completionResponse(content: "not JSON")
    let httpClient = SequencedCustomProviderTestHTTPClient(
      responses: [
        (data: malformedResponse, statusCode: 200),
        (data: malformedResponse, statusCode: 200),
      ]
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: httpClient
    )

    await #expect(
      throws: TranslationError.invalidResponse(
        .malformedPayload,
        diagnosticReason: .responseJSONCouldNotBeDecoded,
        httpStatusCode: 200
      )
    ) {
      try await provider.translate(TranslationRequest(sourceText: "ran"))
    }
    #expect(httpClient.requests.count == 2)
  }

  @Test("cliche response without pronunciation is accepted")
  func clicheResponseWithoutPronunciationIsAccepted() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "cliche",
        "canonical_form": "cliché",
        "part_of_speech": "noun",
        "contextual_meaning": "陈词滥调",
        "example_sentence": "The ending felt like a cliche.",
        "sentence_translation": "这个结局感觉像是陈词滥调。",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: responseContent, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: CustomProviderTestHTTPClient(data: responseBody, statusCode: 200)
    )

    let result = try await provider.translate(TranslationRequest(sourceText: "cliche"))

    #expect(result.canonicalForm == "cliché")
    #expect(result.pronunciation.isEmpty)
    #expect(result.contextualMeaning == "陈词滥调")
  }

  @Test("Mandarin pinyin is discarded without failing the translation")
  func mandarinPinyinIsDiscarded() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "word",
        "canonical_form": "word",
        "pronunciation": "dān cí",
        "part_of_speech": "noun",
        "contextual_meaning": "单词",
        "example_sentence": "This is a word.",
        "sentence_translation": "这是一个单词。",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: responseContent, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: CustomProviderTestHTTPClient(data: responseBody, statusCode: 200)
    )

    let result = try await provider.translate(TranslationRequest(sourceText: "word"))

    #expect(result.pronunciation.isEmpty)
    #expect(result.contextualMeaning == "单词")
  }

  @Test("missing learning content reports its response failure reason")
  func missingLearningContentReportsItsReason() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "cliche",
        "canonical_form": "cliché",
        "pronunciation": "/kliːˈʃeɪ/",
        "part_of_speech": "noun",
        "example_sentence": "The ending felt like a cliche.",
        "sentence_translation": "这个结局感觉像是陈词滥调。",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: responseContent, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://example.com/v1",
        customModel: "example-model"
      ),
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: CustomProviderTestHTTPClient(data: responseBody, statusCode: 200)
    )

    await #expect(
      throws: TranslationError.invalidResponse(
        .missingRequiredContent,
        diagnosticReason: .responseRequiredFieldsMissing,
        missingResponseFields: ["contextual_meaning"],
        httpStatusCode: 200
      )
    ) {
      try await provider.translate(TranslationRequest(sourceText: "cliche"))
    }
  }

  @Test("remote HTTP base URL is rejected before sending the API key")
  func remoteHTTPBaseURLIsRejected() async {
    let httpClient = CustomProviderTestHTTPClient(data: Data(), statusCode: 200)
    let configuration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "http://remote.example/v1",
      customModel: "example-model"
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: configuration,
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "private-api-key"),
      httpClient: httpClient
    )

    await #expect(throws: TranslationError.notConfigured) {
      try await provider.translate(TranslationRequest(sourceText: "ran"))
    }

    #expect(httpClient.lastRequest == nil)
  }
}

private func completionResponse(content: String) throws -> Data {
  try JSONSerialization.data(
    withJSONObject: [
      "choices": [
        ["message": ["content": content]]
      ]
    ]
  )
}

@MainActor
private final class CustomProviderTestHTTPClient: HTTPDataLoading {
  private let data: Data
  private let statusCode: Int
  private(set) var lastRequest: URLRequest?

  init(data: Data, statusCode: Int) {
    self.data = data
    self.statusCode = statusCode
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    lastRequest = request
    let response = try #require(
      HTTPURLResponse(
        url: request.url ?? URL(string: "https://example.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      ))
    return (data, response)
  }
}

@MainActor
private final class SequencedCustomProviderTestHTTPClient: HTTPDataLoading {
  struct Response {
    let data: Data
    let statusCode: Int
  }

  private let responses: [Response]
  private var responseIndex = 0
  private(set) var requests: [URLRequest] = []

  init(responses: [(data: Data, statusCode: Int)]) {
    self.responses = responses.map { Response(data: $0.data, statusCode: $0.statusCode) }
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    precondition(responseIndex < responses.count, "Unexpected extra HTTP request")
    let responseData = responses[responseIndex]
    responseIndex += 1
    let response = try #require(
      HTTPURLResponse(
        url: request.url ?? URL(string: "https://example.com")!,
        statusCode: responseData.statusCode,
        httpVersion: nil,
        headerFields: nil
      ))
    return (responseData.data, response)
  }
}

@MainActor
private struct CustomProviderTestAPIKeyStore: APIKeyStoring {
  let apiKey: String?

  func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
    apiKey
  }

  func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {}
}

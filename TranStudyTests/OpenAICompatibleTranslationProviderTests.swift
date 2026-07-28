import Foundation
import Testing

@testable import TranStudy

@MainActor
struct OpenAICompatibleTranslationProviderTests {
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

    let result = try await provider.translate(
      TranslationRequest(
        sourceText: "ran",
        context: "She ran home.",
        kind: .contextualSelection,
        targetSentence: "She ran home."
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
    let userMessage = try #require(messages.last?["content"])
    #expect(userMessage.contains("ran"))
    #expect(userMessage.contains("She ran home."))
    #expect(userMessage.contains("Return this exact target sentence unchanged"))
    #expect(result.canonicalForm == "run")

    await #expect(throws: TranslationError.invalidResponse) {
      try await provider.translate(
        TranslationRequest(
          sourceText: "ran",
          context: "They ran away.",
          kind: .contextualSelection,
          targetSentence: "They ran away."
        ))
    }
  }

  @Test("structured response must preserve the requested source text")
  func structuredResponseMustPreserveSourceText() async throws {
    let responseContent = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "word_or_phrase",
        "source_text": "different text",
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
    let configuration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "https://example.com/v1",
      customModel: "example-model"
    )
    let provider = OpenAICompatibleTranslationProvider(
      configuration: configuration,
      apiKeyStore: CustomProviderTestAPIKeyStore(apiKey: "custom-api-key"),
      httpClient: CustomProviderTestHTTPClient(data: responseBody, statusCode: 200)
    )

    await #expect(throws: TranslationError.invalidResponse) {
      try await provider.translate(TranslationRequest(sourceText: "ran"))
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

  @Test("Mandarin pinyin is rejected as an invalid English pronunciation")
  func mandarinPinyinIsRejected() async throws {
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

    await #expect(throws: TranslationError.invalidResponse) {
      try await provider.translate(TranslationRequest(sourceText: "word"))
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
private struct CustomProviderTestAPIKeyStore: APIKeyStoring {
  let apiKey: String?

  func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
    apiKey
  }

  func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {}
}

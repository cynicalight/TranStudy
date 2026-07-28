import Foundation
import Testing

@testable import TranStudy

@MainActor
struct DeepSeekTranslationProviderTests {
  @Test("connection fails when the configured model is unavailable")
  func connectionFailsWhenConfiguredModelIsUnavailable() async throws {
    let httpClient = TestHTTPClient(
      data: try JSONSerialization.data(
        withJSONObject: ["data": []]
      ),
      statusCode: 200
    )
    let provider = DeepSeekTranslationProvider(
      apiKeyStore: TestAPIKeyStore(apiKey: nil),
      httpClient: httpClient,
      model: .flash
    )

    await #expect(throws: TranslationError.self) {
      try await provider.testConnection(
        configuration: .default,
        apiKey: "test-api-key"
      )
    }
  }

  @Test("DeepSeek connection test uses the official models endpoint")
  func testsConnectionWithOfficialModelsEndpoint() async throws {
    let httpClient = TestHTTPClient(
      data: try JSONSerialization.data(
        withJSONObject: [
          "data": [
            ["id": "deepseek-v4-flash"]
          ]
        ]
      ),
      statusCode: 200
    )
    let provider = DeepSeekTranslationProvider(
      apiKeyStore: TestAPIKeyStore(apiKey: nil),
      httpClient: httpClient,
      model: .flash
    )

    try await provider.testConnection(
      configuration: .default,
      apiKey: "test-api-key"
    )

    let request = try #require(httpClient.lastRequest)
    #expect(request.url?.absoluteString == "https://api.deepseek.com/models")
    #expect(request.httpMethod == "GET")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
  }

  @Test("DeepSeek request uses the official endpoint and decodes structured learning content")
  func translatesStructuredLearningContent() async throws {
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
    let httpClient = TestHTTPClient(
      data: responseBody,
      statusCode: 200
    )
    let provider = DeepSeekTranslationProvider(
      apiKeyStore: TestAPIKeyStore(apiKey: "test-api-key"),
      httpClient: httpClient,
      model: .flash
    )

    let result = try await provider.translate(
      TranslationRequest(sourceText: "ran")
    )

    let request = try #require(httpClient.lastRequest)
    #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

    let bodyData = try #require(request.httpBody)
    let body = try #require(
      JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    )
    #expect(body["model"] as? String == "deepseek-v4-flash")
    #expect((body["response_format"] as? [String: String])?["type"] == "json_object")
    #expect(
      result
        == TranslationResult(
          sourceText: "ran",
          canonicalForm: "run",
          pronunciation: "/ræn/",
          partOfSpeech: "verb",
          contextualMeaning: "奔跑",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她跑回了家。"
        ))
  }

  @Test("DeepSeek sentence classification cannot create a word result")
  func sentenceClassificationCannotCreateWordResult() async throws {
    let content = try JSONSerialization.data(
      withJSONObject: [
        "input_kind": "long_text",
        "source_text": "She ran home",
        "canonical_form": "",
        "pronunciation": "",
        "part_of_speech": "",
        "contextual_meaning": "",
        "example_sentence": "",
        "sentence_translation": "她跑回了家。",
      ]
    )
    let responseBody = try JSONSerialization.data(
      withJSONObject: [
        "choices": [
          [
            "message": [
              "content": try #require(String(data: content, encoding: .utf8))
            ]
          ]
        ]
      ]
    )
    let provider = DeepSeekTranslationProvider(
      apiKeyStore: TestAPIKeyStore(apiKey: "test-api-key"),
      httpClient: TestHTTPClient(data: responseBody, statusCode: 200),
      model: .flash
    )

    await #expect(throws: TranslationError.self) {
      try await provider.translate(
        TranslationRequest(sourceText: "She ran home")
      )
    }
  }
}

@MainActor
private final class TestHTTPClient: HTTPDataLoading {
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
        url: request.url ?? URL(string: "https://api.deepseek.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
      ))
    return (data, response)
  }
}

@MainActor
private struct TestAPIKeyStore: APIKeyStoring {
  let apiKey: String?

  func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
    apiKey
  }

  func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {}
}

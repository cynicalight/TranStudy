import Foundation
import Testing

@testable import TranStudy

@MainActor
struct ConfiguredTranslationServiceTests {
  @Test("translation uses only the currently selected custom provider")
  func translationUsesSelectedCustomProvider() async throws {
    let configuration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "https://custom.example/v1",
      customModel: "custom-model"
    )
    let httpClient = RoutingTestHTTPClient(
      data: try wordResponse(),
      statusCode: 200
    )
    let service = ConfiguredTranslationService(
      configurationStore: RoutingTestConfigurationStore(configuration: configuration),
      apiKeyStore: RoutingTestAPIKeyStore(
        apiKeys: [
          .deepSeek: "deepseek-key",
          .openAICompatible: "custom-key",
        ]),
      httpClient: httpClient
    )

    _ = try await service.translate(TranslationRequest(sourceText: "ran"))

    #expect(httpClient.requests.count == 1)
    #expect(
      httpClient.requests.first?.url?.absoluteString
        == "https://custom.example/v1/chat/completions"
    )
    #expect(
      httpClient.requests.first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer custom-key"
    )
  }

  @Test("connection test uses a minimal chat completion for the selected custom provider")
  func connectionTestUsesSelectedCustomProvider() async throws {
    let configuration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "https://custom.example/v1",
      customModel: "custom-model"
    )
    let httpClient = RoutingTestHTTPClient(
      data: try JSONSerialization.data(
        withJSONObject: [
          "choices": [
            [
              "message": [
                "content": "OK"
              ]
            ]
          ]
        ]
      ),
      statusCode: 200
    )
    let service = ConfiguredTranslationService(
      configurationStore: RoutingTestConfigurationStore(configuration: configuration),
      apiKeyStore: RoutingTestAPIKeyStore(apiKeys: [:]),
      httpClient: httpClient
    )

    try await service.testConnection(
      configuration: configuration,
      apiKey: "connection-key"
    )

    #expect(httpClient.requests.count == 1)
    #expect(
      httpClient.requests.first?.url?.absoluteString
        == "https://custom.example/v1/chat/completions"
    )
    #expect(httpClient.requests.first?.httpMethod == "POST")
    #expect(
      httpClient.requests.first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer connection-key"
    )
    let requestBody = try #require(httpClient.requests.first?.httpBody)
    let body = try #require(
      JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
    )
    #expect(body["model"] as? String == "custom-model")
  }

  @Test("oversized context and long text are rejected before network access")
  func oversizedInputIsRejectedLocally() async {
    let configuration = TranslationProviderConfiguration.default
    let httpClient = RoutingTestHTTPClient(data: Data(), statusCode: 200)
    let service = ConfiguredTranslationService(
      configurationStore: RoutingTestConfigurationStore(configuration: configuration),
      apiKeyStore: RoutingTestAPIKeyStore(apiKeys: [.deepSeek: "deepseek-key"]),
      httpClient: httpClient
    )

    await #expect(throws: TranslationError.inputTooLong) {
      try await service.translate(
        TranslationRequest(
          sourceText: "ran",
          context: String(repeating: "a", count: 4_001),
          kind: .contextualSelection
        )
      )
    }
    await #expect(throws: TranslationError.inputTooLong) {
      try await service.translate(
        TranslationRequest(
          sourceText: String(repeating: "a", count: 12_001),
          kind: .longText
        )
      )
    }

    #expect(httpClient.requests.isEmpty)
  }

  @Test("cache is exact across provider model text and context")
  func cacheUsesExactTranslationIdentity() async throws {
    let configurationStore = RoutingTestConfigurationStore(
      configuration: TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://custom.example/v1",
        customModel: "custom-model"
      )
    )
    let httpClient = RoutingTestHTTPClient(
      data: try wordResponse(),
      statusCode: 200
    )
    let service = ConfiguredTranslationService(
      configurationStore: configurationStore,
      apiKeyStore: RoutingTestAPIKeyStore(
        apiKeys: [
          .deepSeek: "deepseek-key",
          .openAICompatible: "custom-key",
        ]),
      httpClient: httpClient
    )
    let firstRequest = TranslationRequest(
      sourceText: "ran",
      context: "She ran home.",
      kind: .contextualSelection
    )

    _ = try await service.translate(firstRequest)
    _ = try await service.translate(firstRequest)
    #expect(httpClient.requests.count == 1)

    _ = try await service.translate(
      TranslationRequest(
        sourceText: "ran",
        context: "She ran a company.",
        kind: .contextualSelection
      )
    )
    #expect(httpClient.requests.count == 2)

    configurationStore.save(
      TranslationProviderConfiguration(
        provider: .openAICompatible,
        deepSeekModel: .flash,
        customBaseURL: "https://custom.example/v1",
        customModel: "another-model"
      )
    )
    _ = try await service.translate(firstRequest)
    #expect(httpClient.requests.count == 3)

    configurationStore.save(.default)
    _ = try await service.translate(firstRequest)
    #expect(httpClient.requests.count == 4)
  }

  @Test("timeout is sanitized and does not fall back to another provider")
  func timeoutIsSanitizedWithoutProviderFallback() async {
    let configuration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "https://custom.example/v1",
      customModel: "custom-model"
    )
    let apiKey = "private-custom-key"
    let httpClient = ThrowingRoutingHTTPClient(
      error: URLError(
        .timedOut,
        userInfo: [NSLocalizedDescriptionKey: "request failed with \(apiKey)"]
      )
    )
    let service = ConfiguredTranslationService(
      configurationStore: RoutingTestConfigurationStore(configuration: configuration),
      apiKeyStore: RoutingTestAPIKeyStore(
        apiKeys: [
          .deepSeek: "deepseek-key",
          .openAICompatible: apiKey,
        ]),
      httpClient: httpClient
    )

    do {
      _ = try await service.translate(TranslationRequest(sourceText: "ran"))
      Issue.record("Expected translation to time out")
    } catch let error as TranslationError {
      #expect(error == .timedOut)
      #expect(!String(describing: error).contains(apiKey))
    } catch {
      Issue.record("Expected a sanitized TranslationError")
    }

    #expect(httpClient.requests.count == 1)
    #expect(
      httpClient.requests.first?.url?.absoluteString
        == "https://custom.example/v1/chat/completions"
    )
  }

  @Test("HTTP failures expose an actionable translation error")
  func HTTPFailuresExposeActionableTranslationErrors() async throws {
    let cases: [(
      statusCode: Int,
      response: String,
      expected: TranslationError,
      reason: DiagnosticTranslationFailureReason
    )] = [
      (400, "bad request", .httpFailure(.invalidRequest, statusCode: 400), .requestRejected),
      (
        401,
        "unauthorized",
        .httpFailure(.authenticationFailed, statusCode: 401),
        .authenticationFailed
      ),
      (
        402,
        "insufficient balance",
        .httpFailure(.quotaExceeded, statusCode: 402),
        .quotaExceeded
      ),
      (
        413,
        "payload too large",
        .httpFailure(.inputTooLong, statusCode: 413),
        .inputExceedsTranslationLimit
      ),
      (429, "rate limit exceeded", .httpFailure(.rateLimited, statusCode: 429), .rateLimited),
      (
        429,
        "insufficient_quota",
        .httpFailure(.quotaExceeded, statusCode: 429),
        .quotaExceeded
      ),
      (
        503,
        "service unavailable",
        .httpFailure(.serviceUnavailable, statusCode: 503),
        .serviceUnavailable
      ),
    ]

    for testCase in cases {
      let service = ConfiguredTranslationService(
        configurationStore: RoutingTestConfigurationStore(configuration: .default),
        apiKeyStore: RoutingTestAPIKeyStore(apiKeys: [.deepSeek: "deepseek-key"]),
        httpClient: RoutingTestHTTPClient(
          data: Data(testCase.response.utf8),
          statusCode: testCase.statusCode
        )
      )

      do {
        _ = try await service.translate(TranslationRequest(sourceText: "ran"))
        Issue.record("Expected HTTP \(testCase.statusCode) to fail")
      } catch let error as TranslationError {
        #expect(error == testCase.expected)
        #expect(error.diagnosticFailureReason == testCase.reason)
        #expect(error.httpStatusCode == testCase.statusCode)
      }
    }
  }

  @Test("cancelling translation cancels the in-flight HTTP operation")
  func cancellationStopsHTTPWork() async {
    let httpClient = CancellationTrackingHTTPClient()
    let service = ConfiguredTranslationService(
      configurationStore: RoutingTestConfigurationStore(configuration: .default),
      apiKeyStore: RoutingTestAPIKeyStore(apiKeys: [.deepSeek: "deepseek-key"]),
      httpClient: httpClient
    )
    let task = Task {
      try await service.translate(TranslationRequest(sourceText: "ran"))
    }
    for _ in 0..<10 where !httpClient.hasStarted {
      await Task.yield()
    }
    #expect(httpClient.hasStarted)

    task.cancel()
    await #expect(throws: CancellationError.self) {
      try await task.value
    }

    #expect(httpClient.wasCancelled)
  }

  private func wordResponse() throws -> Data {
    let content = try JSONSerialization.data(
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
    return try JSONSerialization.data(
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
  }
}

@MainActor
private final class RoutingTestHTTPClient: HTTPDataLoading {
  private let data: Data
  private let statusCode: Int
  private(set) var requests: [URLRequest] = []

  init(data: Data, statusCode: Int) {
    self.data = data
    self.statusCode = statusCode
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
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
private final class ThrowingRoutingHTTPClient: HTTPDataLoading {
  private let error: any Error
  private(set) var requests: [URLRequest] = []

  init(error: any Error) {
    self.error = error
  }

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    requests.append(request)
    throw error
  }
}

@MainActor
private final class CancellationTrackingHTTPClient: HTTPDataLoading {
  private(set) var hasStarted = false
  private(set) var wasCancelled = false

  func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    hasStarted = true

    do {
      try await Task.sleep(for: .seconds(60))
      throw TranslationError.serviceUnavailable
    } catch is CancellationError {
      wasCancelled = true
      throw CancellationError()
    }
  }
}

private final class RoutingTestConfigurationStore: TranslationProviderConfigurationStoring {
  private var configuration: TranslationProviderConfiguration

  init(configuration: TranslationProviderConfiguration) {
    self.configuration = configuration
  }

  func load() -> TranslationProviderConfiguration {
    configuration
  }

  func save(_ configuration: TranslationProviderConfiguration) {
    self.configuration = configuration
  }
}

@MainActor
private struct RoutingTestAPIKeyStore: APIKeyStoring {
  let apiKeys: [TranslationProviderKind: String]

  func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
    apiKeys[provider]
  }

  func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {}
}

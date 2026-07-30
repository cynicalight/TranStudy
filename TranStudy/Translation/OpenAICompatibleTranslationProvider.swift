import Foundation

@MainActor
final class OpenAICompatibleTranslationProvider:
  TranslationConnectionTesting,
  TranslationProviding
{
  private let configuration: TranslationProviderConfiguration
  private let apiKeyStore: any APIKeyStoring
  private let httpClient: any HTTPDataLoading

  init(
    configuration: TranslationProviderConfiguration,
    apiKeyStore: any APIKeyStoring,
    httpClient: any HTTPDataLoading
  ) {
    self.configuration = configuration
    self.apiKeyStore = apiKeyStore
    self.httpClient = httpClient
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    guard
      configuration.provider == .openAICompatible,
      let baseURL = Self.validBaseURL(configuration.customBaseURL),
      !configuration.customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw TranslationError.notConfigured
    }
    return try await OpenAIChatTranslationClient(
      provider: .openAICompatible,
      endpoint: baseURL.appending(path: "chat/completions"),
      model: configuration.customModel,
      addsDisabledThinking: false,
      apiKeyStore: apiKeyStore,
      httpClient: httpClient
    ).translate(request)
  }

  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult {
    guard
      configuration.provider == .openAICompatible,
      let baseURL = Self.validBaseURL(configuration.customBaseURL),
      !configuration.customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw TranslationError.notConfigured
    }
    return try await OpenAIChatTranslationClient(
      provider: .openAICompatible,
      endpoint: baseURL.appending(path: "chat/completions"),
      model: configuration.customModel,
      addsDisabledThinking: false,
      apiKeyStore: apiKeyStore,
      httpClient: httpClient
    ).translateLongText(
      sourceText,
      chineseWritingSystem: chineseWritingSystem
    )
  }

  func testConnection(
    configuration: TranslationProviderConfiguration,
    apiKey: String
  ) async throws {
    guard
      configuration.provider == .openAICompatible,
      configuration == self.configuration,
      let baseURL = Self.validBaseURL(configuration.customBaseURL),
      !configuration.customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      throw TranslationError.notConfigured
    }

    var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONEncoder().encode(
      CompatibleConnectionRequest(
        model: configuration.customModel,
        messages: [
          OpenAIMessage(role: "user", content: "Reply with OK.")
        ],
        maxTokens: 1
      ))

    let (data, response) = try await httpClient.data(for: request)
    guard (200..<300).contains(response.statusCode) else {
      throw TranslationError.serviceUnavailable
    }
    guard
      let completion = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data),
      let content = completion.choices.first?.message.content,
      !content.isEmpty
    else {
      throw TranslationError.invalidResponse
    }
  }

  private static func validBaseURL(_ value: String) -> URL? {
    guard
      let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
      let scheme = url.scheme?.lowercased(),
      ["http", "https"].contains(scheme),
      url.host != nil
    else {
      return nil
    }
    if scheme == "http" {
      let localHosts = ["localhost", "127.0.0.1", "::1"]
      guard localHosts.contains(url.host?.lowercased() ?? "") else {
        return nil
      }
    }

    return url
  }

}

private struct CompatibleConnectionRequest: Encodable {
  let model: String
  let messages: [OpenAIMessage]
  let maxTokens: Int

  enum CodingKeys: String, CodingKey {
    case model
    case messages
    case maxTokens = "max_tokens"
  }
}

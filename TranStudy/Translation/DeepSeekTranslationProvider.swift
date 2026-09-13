import Foundation

enum DeepSeekModel: String, CaseIterable, Codable, Identifiable, Sendable {
  case flash = "deepseek-flash"
  case pro = "deepseek-v4-pro"

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawValue = try container.decode(String.self)
    // Preserve configurations saved before the Flash model was renamed.
    if rawValue == "deepseek-v4-flash" {
      self = .flash
    } else if let model = Self(rawValue: rawValue) {
      self = model
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unknown DeepSeek model: \(rawValue)"
      )
    }
  }

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .flash:
      "DeepSeek Flash"
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
    try await OpenAIChatTranslationClient(
      provider: .deepSeek,
      endpoint: endpoint,
      model: model.rawValue,
      addsDisabledThinking: true,
      apiKeyStore: apiKeyStore,
      httpClient: httpClient
    ).translate(request)
  }

  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult {
    try await OpenAIChatTranslationClient(
      provider: .deepSeek,
      endpoint: endpoint,
      model: model.rawValue,
      addsDisabledThinking: true,
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
      configuration.provider == .deepSeek,
      configuration.deepSeekModel == model
    else {
      throw TranslationError.notConfigured
    }

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
      throw TranslationError.invalidResponse(.malformedPayload)
    }

    guard modelList.data.contains(where: { $0.id == model.rawValue }) else {
      throw TranslationError.serviceUnavailable
    }
  }

}

private struct ModelList: Decodable {
  let data: [AvailableModel]
}

private struct AvailableModel: Decodable {
  let id: String
}

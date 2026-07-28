import Foundation

@MainActor
final class ConfiguredTranslationService:
  TranslationConnectionTesting,
  TranslationProviding
{
  private let configurationStore: any TranslationProviderConfigurationStoring
  private let apiKeyStore: any APIKeyStoring
  private let httpClient: any HTTPDataLoading
  private let cacheStore: any TranslationCacheStoring

  init(
    configurationStore: any TranslationProviderConfigurationStoring,
    apiKeyStore: any APIKeyStoring,
    httpClient: any HTTPDataLoading,
    cacheStore: any TranslationCacheStoring = InMemoryTranslationCacheStore()
  ) {
    self.configurationStore = configurationStore
    self.apiKeyStore = apiKeyStore
    self.httpClient = httpClient
    self.cacheStore = cacheStore
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    try validate(request)
    let configuration = configurationStore.load()
    let cacheKey = TranslationCacheKey(configuration: configuration, request: request)
    if let cachedResult = cacheStore.value(for: cacheKey) {
      return cachedResult
    }

    let result = try await sanitizeErrors {
      switch configuration.provider {
      case .deepSeek:
        return try await DeepSeekTranslationProvider(
          apiKeyStore: apiKeyStore,
          httpClient: httpClient,
          model: configuration.deepSeekModel
        ).translate(request)
      case .openAICompatible:
        return try await OpenAICompatibleTranslationProvider(
          configuration: configuration,
          apiKeyStore: apiKeyStore,
          httpClient: httpClient
        ).translate(request)
      }
    }

    cacheStore.insert(result, for: cacheKey)
    return result
  }

  private func validate(_ request: TranslationRequest) throws {
    if let context = request.context,
      context.count > 4_000 || Self.estimatedTokenCount(context) > 1_200
    {
      throw TranslationError.inputTooLong
    }

    if request.kind == .longText,
      request.sourceText.count > 12_000
        || Self.estimatedTokenCount(request.sourceText) > 3_500
    {
      throw TranslationError.inputTooLong
    }
  }

  private static func estimatedTokenCount(_ text: String) -> Int {
    max(1, (text.utf8.count + 3) / 4)
  }

  func testConnection(
    configuration: TranslationProviderConfiguration,
    apiKey: String
  ) async throws {
    try await sanitizeErrors {
      switch configuration.provider {
      case .deepSeek:
        try await DeepSeekTranslationProvider(
          apiKeyStore: apiKeyStore,
          httpClient: httpClient,
          model: configuration.deepSeekModel
        ).testConnection(configuration: configuration, apiKey: apiKey)
      case .openAICompatible:
        try await OpenAICompatibleTranslationProvider(
          configuration: configuration,
          apiKeyStore: apiKeyStore,
          httpClient: httpClient
        ).testConnection(configuration: configuration, apiKey: apiKey)
      }
    }
  }

  private func sanitizeErrors<T>(
    _ operation: () async throws -> T
  ) async throws -> T {
    do {
      return try await operation()
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as TranslationError {
      throw error
    } catch let error as URLError {
      if error.code == .timedOut {
        throw TranslationError.timedOut
      }
      throw TranslationError.networkUnavailable
    } catch {
      throw TranslationError.networkUnavailable
    }
  }
}

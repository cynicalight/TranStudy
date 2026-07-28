@MainActor
protocol TranslationConnectionTesting {
  func testConnection(
    configuration: TranslationProviderConfiguration,
    apiKey: String
  ) async throws
}

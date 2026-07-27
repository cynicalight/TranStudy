@MainActor
protocol TranslationConnectionTesting {
  func testConnection(apiKey: String) async throws
}

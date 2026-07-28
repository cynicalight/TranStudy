@MainActor
protocol APIKeyStoring {
  func loadAPIKey(for provider: TranslationProviderKind) throws -> String?
  func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws
}

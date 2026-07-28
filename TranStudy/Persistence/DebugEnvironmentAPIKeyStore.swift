#if DEBUG
  import Foundation

  @MainActor
  final class DebugEnvironmentAPIKeyStore: APIKeyStoring {
    private let fallback: any APIKeyStoring
    private let deepSeekAPIKey: String?

    init(
      fallback: any APIKeyStoring,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
      self.fallback = fallback
      deepSeekAPIKey =
        environment["DEEPSEEK_API_KEY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
      if provider == .deepSeek,
        let deepSeekAPIKey,
        !deepSeekAPIKey.isEmpty
      {
        return deepSeekAPIKey
      }

      return try fallback.loadAPIKey(for: provider)
    }

    func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {
      try fallback.saveAPIKey(apiKey, for: provider)
    }
  }
#endif

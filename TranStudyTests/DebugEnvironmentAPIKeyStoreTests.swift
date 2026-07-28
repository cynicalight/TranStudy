#if DEBUG
  import Testing

  @testable import TranStudy

  @MainActor
  struct DebugEnvironmentAPIKeyStoreTests {
    @Test("Debug environment key overrides only the DeepSeek Keychain value")
    func deepSeekEnvironmentKeyTakesPrecedence() throws {
      let fallback = StubAPIKeyStore(
        values: [
          .deepSeek: "keychain-deepseek-key",
          .openAICompatible: "keychain-custom-key",
        ])
      let store = DebugEnvironmentAPIKeyStore(
        fallback: fallback,
        environment: ["DEEPSEEK_API_KEY": "  environment-key  "]
      )

      #expect(try store.loadAPIKey(for: .deepSeek) == "environment-key")
      #expect(try store.loadAPIKey(for: .openAICompatible) == "keychain-custom-key")
    }

    @Test("An empty Debug environment key falls back to Keychain")
    func emptyEnvironmentKeyFallsBackToKeychain() throws {
      let fallback = StubAPIKeyStore(values: [.deepSeek: "keychain-deepseek-key"])
      let store = DebugEnvironmentAPIKeyStore(
        fallback: fallback,
        environment: ["DEEPSEEK_API_KEY": " \n "]
      )

      #expect(try store.loadAPIKey(for: .deepSeek) == "keychain-deepseek-key")
    }

    @Test("Saving a key still writes to Keychain")
    func savingStillUsesKeychain() throws {
      let fallback = StubAPIKeyStore(values: [:])
      let store = DebugEnvironmentAPIKeyStore(
        fallback: fallback,
        environment: ["DEEPSEEK_API_KEY": "environment-key"]
      )

      try store.saveAPIKey("saved-key", for: .deepSeek)

      #expect(fallback.values[.deepSeek] == "saved-key")
    }
  }

  @MainActor
  private final class StubAPIKeyStore: APIKeyStoring {
    var values: [TranslationProviderKind: String]

    init(values: [TranslationProviderKind: String]) {
      self.values = values
    }

    func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
      values[provider]
    }

    func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {
      values[provider] = apiKey
    }
  }
#endif

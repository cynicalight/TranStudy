import Foundation
import Testing

@testable import TranStudy

struct TranslationProviderConfigurationTests {
  @Test("provider configuration defaults to DeepSeek and persists one active provider")
  func providerConfigurationDefaultsAndPersists() {
    let suiteName = "TranslationProviderConfigurationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsTranslationProviderConfigurationStore(defaults: defaults)

    #expect(store.load() == .default)

    let customConfiguration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .pro,
      customBaseURL: "https://example.com/v1",
      customModel: "example-model"
    )
    store.save(customConfiguration)

    #expect(store.load() == customConfiguration)
    #expect(store.load().provider == .openAICompatible)
  }
}

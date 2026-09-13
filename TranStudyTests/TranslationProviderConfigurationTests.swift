import Foundation
import Testing

@testable import TranStudy

struct TranslationProviderConfigurationTests {
  @Test("legacy Flash settings preserve the active provider and save the renamed model")
  func legacyFlashSettingsMigrateWithoutResettingConfiguration() throws {
    let suiteName = "TranslationProviderConfigurationTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let legacyData = Data(
      """
      {
        "provider": "openAICompatible",
        "deepSeekModel": "deepseek-v4-flash",
        "customBaseURL": "https://example.com/v1",
        "customModel": "example-model"
      }
      """.utf8
    )
    defaults.set(legacyData, forKey: "translationProviderConfiguration")
    let store = UserDefaultsTranslationProviderConfigurationStore(defaults: defaults)

    let configuration = store.load()
    #expect(configuration.provider == .openAICompatible)
    #expect(configuration.deepSeekModel == .flash)
    #expect(configuration.customBaseURL == "https://example.com/v1")
    #expect(configuration.customModel == "example-model")

    store.save(configuration)
    let savedData = try #require(defaults.data(forKey: "translationProviderConfiguration"))
    let savedConfiguration = try #require(
      JSONSerialization.jsonObject(with: savedData) as? [String: String]
    )
    #expect(savedConfiguration["deepSeekModel"] == "deepseek-flash")
    #expect(store.load() == configuration)
  }

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

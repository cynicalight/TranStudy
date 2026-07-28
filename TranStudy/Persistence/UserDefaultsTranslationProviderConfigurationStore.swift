import Foundation

struct UserDefaultsTranslationProviderConfigurationStore:
  TranslationProviderConfigurationStoring
{
  private static let key = "translationProviderConfiguration"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> TranslationProviderConfiguration {
    guard
      let data = defaults.data(forKey: Self.key),
      let configuration = try? JSONDecoder().decode(
        TranslationProviderConfiguration.self,
        from: data
      )
    else {
      return .default
    }

    return configuration
  }

  func save(_ configuration: TranslationProviderConfiguration) {
    guard let data = try? JSONEncoder().encode(configuration) else {
      return
    }

    defaults.set(data, forKey: Self.key)
  }
}

protocol TranslationProviderConfigurationStoring {
  func load() -> TranslationProviderConfiguration
  func save(_ configuration: TranslationProviderConfiguration)
}

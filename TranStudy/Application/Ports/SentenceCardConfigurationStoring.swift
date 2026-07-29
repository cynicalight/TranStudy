protocol SentenceCardConfigurationStoring {
  func load() -> Bool
  func save(_ isEnabled: Bool)
}

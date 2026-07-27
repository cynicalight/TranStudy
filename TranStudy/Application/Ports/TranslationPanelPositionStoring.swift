protocol TranslationPanelPositionStoring {
  func load() -> TranslationPanelPosition
  func save(_ position: TranslationPanelPosition)
}

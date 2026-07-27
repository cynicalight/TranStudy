import Foundation

struct UserDefaultsTranslationPanelPositionStore: TranslationPanelPositionStoring {
  private static let key = "translationPanelPosition"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> TranslationPanelPosition {
    guard
      let rawValue = defaults.string(forKey: Self.key),
      let position = TranslationPanelPosition(rawValue: rawValue)
    else {
      return .topTrailing
    }

    return position
  }

  func save(_ position: TranslationPanelPosition) {
    defaults.set(position.rawValue, forKey: Self.key)
  }
}

import Foundation

struct UserDefaultsTranslationShortcutStore: TranslationShortcutStoring {
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "translation-shortcut-v1"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> TranslationShortcutKey {
    guard
      let rawValue = defaults.string(forKey: key),
      let shortcut = TranslationShortcutKey(rawValue: rawValue)
    else {
      return .default
    }
    return shortcut
  }

  func save(_ shortcut: TranslationShortcutKey) {
    defaults.set(shortcut.rawValue, forKey: key)
  }
}

import Foundation

struct UserDefaultsSentenceCardConfigurationStore:
  SentenceCardConfigurationStoring
{
  private let defaults: UserDefaults
  private let key = "sentence-cards-enabled"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> Bool {
    defaults.bool(forKey: key)
  }

  func save(_ isEnabled: Bool) {
    defaults.set(isEnabled, forKey: key)
  }
}

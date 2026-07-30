import Foundation

final class UserDefaultsLanguageAndSpeechPreferencesStore:
  LanguageAndSpeechPreferencesStoring
{
  private enum Key {
    static let preferences = "languageAndSpeech.preferences"
  }

  private let defaults: UserDefaults
  private let encoder = JSONEncoder()
  private let decoder = JSONDecoder()

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func load() -> LanguageAndSpeechPreferences {
    guard
      let data = defaults.data(forKey: Key.preferences),
      let preferences = try? decoder.decode(LanguageAndSpeechPreferences.self, from: data)
    else {
      return .default
    }
    return preferences
  }

  func save(_ preferences: LanguageAndSpeechPreferences) {
    guard let data = try? encoder.encode(preferences) else {
      return
    }
    defaults.set(data, forKey: Key.preferences)
  }
}

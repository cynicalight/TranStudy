protocol LanguageAndSpeechPreferencesStoring {
  func load() -> LanguageAndSpeechPreferences
  func save(_ preferences: LanguageAndSpeechPreferences)
}

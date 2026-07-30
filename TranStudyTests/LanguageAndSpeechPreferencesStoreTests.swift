import Foundation
import Testing

@testable import TranStudy

struct LanguageAndSpeechPreferencesStoreTests {
  @Test("preferences default safely and persist as one value")
  func preferencesDefaultAndPersist() throws {
    let suiteName = "LanguageAndSpeechPreferencesStoreTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsLanguageAndSpeechPreferencesStore(defaults: defaults)

    #expect(store.load() == .default)

    let preferences = LanguageAndSpeechPreferences(
      interfaceLanguage: .traditionalChinese,
      chineseWritingSystem: .traditional,
      speechVoiceIdentifier: "voice.en-GB",
      speechRate: 0.58,
      automaticallySpeaksTranslations: true
    )
    store.save(preferences)

    #expect(store.load() == preferences)
  }
}

import AppKit
import Foundation

struct ApplicationEnvironment {
  let selection: any SelectionProviding
  let clipboard: any ClipboardReading
  let translation: any TranslationProviding
  let learningStore: any LearningStoring
  let apiKeyStore: any APIKeyStoring
  let connectionTester: any TranslationConnectionTesting
  let clock: any DateProviding
  let notifications: any ReviewNotifying
  let accessibilityAuthorization: any AccessibilityAuthorizing
  let reviewReminderConfigurationStore: any ReviewReminderConfigurationStoring
  let loginItem: any LoginItemControlling
  let speech: any SpeechPlaying
  let panelPositionStore: any TranslationPanelPositionStoring
  let providerConfigurationStore: any TranslationProviderConfigurationStoring
  let selectionConfigurationStore: any SelectionConfigurationStoring
  let shortcutStore: any TranslationShortcutStoring
  let sentenceCardConfigurationStore: any SentenceCardConfigurationStoring
  let preparationStateStore: any PreparationStateStoring
}

extension ApplicationEnvironment {
  @MainActor
  static func live(
    learningStore: any LearningStoring,
    translation: any TranslationProviding,
    apiKeyStore: any APIKeyStoring,
    connectionTester: any TranslationConnectionTesting,
    providerConfigurationStore: any TranslationProviderConfigurationStoring,
    notifications: any ReviewNotifying
  ) -> ApplicationEnvironment {
    let selectionConfigurationStore = UserDefaultsSelectionConfigurationStore()
    return ApplicationEnvironment(
      selection: AccessibilitySelectionProvider(
        configurationStore: selectionConfigurationStore
      ),
      clipboard: SystemClipboardReader(),
      translation: translation,
      learningStore: learningStore,
      apiKeyStore: apiKeyStore,
      connectionTester: connectionTester,
      clock: SystemDateProvider(),
      notifications: notifications,
      accessibilityAuthorization: SystemAccessibilityAuthorizer(),
      reviewReminderConfigurationStore: UserDefaultsReviewReminderConfigurationStore(),
      loginItem: SystemLoginItemController(),
      speech: DisabledSpeechPlayer(),
      panelPositionStore: UserDefaultsTranslationPanelPositionStore(),
      providerConfigurationStore: providerConfigurationStore,
      selectionConfigurationStore: selectionConfigurationStore,
      shortcutStore: UserDefaultsTranslationShortcutStore(),
      sentenceCardConfigurationStore: UserDefaultsSentenceCardConfigurationStore(),
      preparationStateStore: UserDefaultsPreparationStateStore()
    )
  }
}

private struct SystemClipboardReader: ClipboardReading {
  func readText() -> String? {
    NSPasteboard.general.string(forType: .string)
  }
}

private struct SystemDateProvider: DateProviding {
  var now: Date {
    Date()
  }
}

private struct DisabledSpeechPlayer: SpeechPlaying {
  func speak(_ text: String) {}
}

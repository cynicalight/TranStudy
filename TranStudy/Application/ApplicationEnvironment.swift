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
  let speech: any SpeechPlaying
  let panelPositionStore: any TranslationPanelPositionStoring
}

extension ApplicationEnvironment {
  @MainActor
  static func live(
    learningStore: any LearningStoring,
    translation: any TranslationProviding,
    apiKeyStore: any APIKeyStoring,
    connectionTester: any TranslationConnectionTesting
  ) -> ApplicationEnvironment {
    ApplicationEnvironment(
      selection: UnavailableSelectionProvider(),
      clipboard: SystemClipboardReader(),
      translation: translation,
      learningStore: learningStore,
      apiKeyStore: apiKeyStore,
      connectionTester: connectionTester,
      clock: SystemDateProvider(),
      notifications: DisabledReviewNotifier(),
      speech: DisabledSpeechPlayer(),
      panelPositionStore: UserDefaultsTranslationPanelPositionStore()
    )
  }
}

private struct UnavailableSelectionProvider: SelectionProviding {
  func currentSelection() async -> SelectionSnapshot? {
    nil
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

private struct DisabledReviewNotifier: ReviewNotifying {
  func schedule(_ reminder: ReviewReminder) async throws {}
}

private struct DisabledSpeechPlayer: SpeechPlaying {
  func speak(_ text: String) {}
}

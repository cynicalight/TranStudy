import AppKit
import Foundation

struct ApplicationEnvironment {
  let selection: any SelectionProviding
  let clipboard: any ClipboardReading
  let translation: any TranslationProviding
  let learningStore: any LearningStoring
  let clock: any DateProviding
  let notifications: any ReviewNotifying
  let speech: any SpeechPlaying
}

extension ApplicationEnvironment {
  @MainActor
  static func live(learningStore: any LearningStoring) -> ApplicationEnvironment {
    ApplicationEnvironment(
      selection: UnavailableSelectionProvider(),
      clipboard: SystemClipboardReader(),
      translation: UnconfiguredTranslationProvider(),
      learningStore: learningStore,
      clock: SystemDateProvider(),
      notifications: DisabledReviewNotifier(),
      speech: DisabledSpeechPlayer()
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

private struct UnconfiguredTranslationProvider: TranslationProviding {
  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    throw TranslationError.notConfigured
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

import Foundation
import Testing

@testable import TranStudy

@MainActor
struct ApplicationShellTests {
  @Test("app launch refreshes today's review through replaceable boundaries")
  func appLaunchRefreshesTodayReview() async throws {
    let notifier = TestReviewNotifier()
    let shell = ApplicationShell(environment: .test(notifier: notifier))

    #expect(
      shell.destinations == [
        .todayReview,
        .library,
        .settings,
      ])
    #expect(shell.selectedDestination == .todayReview)

    await shell.refreshTodayReview()

    #expect(
      shell.learningSummary
        == LearningSummary(
          dueCount: 3,
          wordCount: 12,
          sentenceCount: 4
        ))
    #expect(shell.lastReviewRefreshDate == Date(timeIntervalSince1970: 1_234))
    #expect(notifier.lastReminder == nil)
  }
}

extension ApplicationEnvironment {
  fileprivate static func test(notifier: TestReviewNotifier) -> ApplicationEnvironment {
    ApplicationEnvironment(
      selection: TestSelectionProvider(),
      clipboard: TestClipboardReader(),
      translation: TestTranslationProvider(),
      learningStore: TestLearningStore(),
      clock: TestClock(),
      notifications: notifier,
      speech: TestSpeechPlayer()
    )
  }
}

private struct TestSelectionProvider: SelectionProviding {
  func currentSelection() async -> SelectionSnapshot? {
    nil
  }
}

private struct TestClipboardReader: ClipboardReading {
  func readText() -> String? {
    nil
  }
}

private struct TestTranslationProvider: TranslationProviding {
  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    throw TranslationError.notConfigured
  }
}

private struct TestLearningStore: LearningStoring {
  func summary() async throws -> LearningSummary {
    LearningSummary(
      dueCount: 3,
      wordCount: 12,
      sentenceCount: 4
    )
  }
}

private struct TestClock: DateProviding {
  var now: Date {
    Date(timeIntervalSince1970: 1_234)
  }
}

private final class TestReviewNotifier: ReviewNotifying {
  var lastReminder: ReviewReminder?

  func schedule(_ reminder: ReviewReminder) async throws {
    lastReminder = reminder
  }
}

private struct TestSpeechPlayer: SpeechPlaying {
  func speak(_ text: String) {}
}

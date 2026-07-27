import Foundation
import Testing

@testable import TranStudy

@MainActor
struct ApplicationShellTests {
  @Test("clipboard translation creates an editable session draft")
  func clipboardTranslationCreatesEditableSessionDraft() async throws {
    let clipboard = TestClipboardReader(text: "  ran  ")
    let translator = TestTranslationProvider(
      result: TranslationResult(
        sourceText: "ran",
        canonicalForm: "run",
        pronunciation: "/ræn/",
        partOfSpeech: "verb",
        contextualMeaning: "跑",
        exampleSentence: "She ran home.",
        sentenceTranslation: "她跑回了家。"
      ))
    let shell = ApplicationShell(
      environment: .test(
        clipboard: clipboard,
        translation: translator
      ))

    await shell.translateClipboard()

    #expect(translator.lastRequest == TranslationRequest(sourceText: "ran"))
    #expect(
      shell.translationDraft
        == TranslationDraft(
          sourceText: "ran",
          canonicalForm: "run",
          pronunciation: "/ræn/",
          partOfSpeech: "verb",
          contextualMeaning: "跑",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她跑回了家。"
        ))

    shell.translationDraft?.contextualMeaning = "奔跑"

    #expect(shell.translationDraft?.contextualMeaning == "奔跑")
  }

  @Test("only joining learning persists the edited session draft")
  func onlyJoiningLearningPersistsEditedSessionDraft() async throws {
    let learningStore = TestLearningStore()
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "ran"),
        translation: TestTranslationProvider(
          result: TranslationResult(
            sourceText: "ran",
            canonicalForm: "run",
            pronunciation: "/ræn/",
            partOfSpeech: "verb",
            contextualMeaning: "跑",
            exampleSentence: "She ran home.",
            sentenceTranslation: "她跑回了家。"
          )),
        learningStore: learningStore
      ))

    await shell.translateClipboard()
    shell.translationDraft?.contextualMeaning = "奔跑"

    #expect(learningStore.lastAddition == nil)

    await shell.addCurrentDraftToLearning()

    #expect(
      learningStore.lastAddition
        == LearningAddition(
          draft: TranslationDraft(
            sourceText: "ran",
            canonicalForm: "run",
            pronunciation: "/ræn/",
            partOfSpeech: "verb",
            contextualMeaning: "奔跑",
            exampleSentence: "She ran home.",
            sentenceTranslation: "她跑回了家。"
          ),
          sourceApplicationName: "剪贴板",
          createdAt: Date(timeIntervalSince1970: 1_234)
        ))
    #expect(shell.translationDraft == nil)
  }

  @Test("a successful DeepSeek connection saves the API key")
  func successfulDeepSeekConnectionSavesAPIKey() async {
    let apiKeyStore = TestApplicationAPIKeyStore()
    let connectionTester = TestTranslationConnectionTester()
    let shell = ApplicationShell(
      environment: .test(
        apiKeyStore: apiKeyStore,
        connectionTester: connectionTester
      ))

    await shell.testDeepSeekConnection(apiKey: "  test-api-key  ")

    #expect(connectionTester.lastAPIKey == "test-api-key")
    #expect(apiKeyStore.savedAPIKey == "test-api-key")
    #expect(shell.connectionStatus == .connected)
  }

  @Test("refreshing the library publishes persisted learning items")
  func refreshingLibraryPublishesPersistedItems() async {
    let expectedItem = LearningItem(
      id: UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!,
      sourceText: "ran",
      canonicalForm: "run",
      pronunciation: "/ræn/",
      partOfSpeech: "verb",
      contextualMeaning: "奔跑",
      exampleSentence: "She ran home.",
      sentenceTranslation: "她跑回了家。",
      sourceApplicationName: "剪贴板",
      createdAt: Date(timeIntervalSince1970: 1_234)
    )
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(items: [expectedItem])
      ))

    await shell.refreshLibrary()

    #expect(shell.learningItems == [expectedItem])
  }

  @Test("a cancelled translation cannot publish a late result")
  func cancelledTranslationCannotPublishLateResult() async {
    let translator = ControlledTranslationProvider()
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "ran"),
        translation: translator
      ))
    let task = Task {
      await shell.translateClipboard()
    }
    await Task.yield()
    #expect(translator.hasPendingRequest)

    task.cancel()
    translator.complete(
      with: TranslationResult(
        sourceText: "ran",
        canonicalForm: "run",
        pronunciation: "/ræn/",
        partOfSpeech: "verb",
        contextualMeaning: "跑",
        exampleSentence: "She ran home.",
        sentenceTranslation: "她跑回了家。"
      ))
    await task.value

    #expect(shell.translationDraft == nil)
    #expect(shell.translationStatus == .idle)
  }

  @Test("sentence clipboard content waits for the long-text issue")
  func sentenceClipboardContentDoesNotCreateAWordDraft() async {
    let translator = TestTranslationProvider()
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "She ran home."),
        translation: translator
      ))

    await shell.translateClipboard()

    #expect(translator.lastRequest == nil)
    #expect(shell.translationDraft == nil)
    #expect(shell.translationStatus == .failed)
  }

  @Test("closing the translation panel cancels its in-flight request")
  func closingTranslationPanelCancelsInFlightRequest() async {
    let translator = ControlledTranslationProvider()
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "ran"),
        translation: translator
      ))
    let controller = TranslationPanelController(shell: shell)

    controller.presentClipboardTranslation()
    for _ in 0..<10 where !translator.hasPendingRequest {
      await Task.yield()
    }
    #expect(translator.hasPendingRequest)

    controller.dismiss()
    translator.complete(
      with: TranslationResult(
        sourceText: "ran",
        canonicalForm: "run",
        pronunciation: "/ræn/",
        partOfSpeech: "verb",
        contextualMeaning: "跑",
        exampleSentence: "She ran home.",
        sentenceTranslation: "她跑回了家。"
      ))
    await Task.yield()

    #expect(shell.translationDraft == nil)
    #expect(shell.translationStatus == .idle)
  }

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
  @MainActor
  fileprivate static func test(
    clipboard: TestClipboardReader = TestClipboardReader(),
    translation: any TranslationProviding = TestTranslationProvider(),
    learningStore: TestLearningStore = TestLearningStore(),
    apiKeyStore: TestApplicationAPIKeyStore = TestApplicationAPIKeyStore(),
    connectionTester: TestTranslationConnectionTester = TestTranslationConnectionTester(),
    notifier: TestReviewNotifier = TestReviewNotifier()
  ) -> ApplicationEnvironment {
    ApplicationEnvironment(
      selection: TestSelectionProvider(),
      clipboard: clipboard,
      translation: translation,
      learningStore: learningStore,
      apiKeyStore: apiKeyStore,
      connectionTester: connectionTester,
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
  var text: String?

  init(text: String? = nil) {
    self.text = text
  }

  func readText() -> String? {
    text
  }
}

@MainActor
private final class TestTranslationProvider: TranslationProviding {
  private let result: TranslationResult?
  private(set) var lastRequest: TranslationRequest?

  init(result: TranslationResult? = nil) {
    self.result = result
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    lastRequest = request

    guard let result else {
      throw TranslationError.notConfigured
    }

    return result
  }
}

@MainActor
private final class ControlledTranslationProvider: TranslationProviding {
  private var continuation: CheckedContinuation<TranslationResult, any Error>?

  var hasPendingRequest: Bool {
    continuation != nil
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
    }
  }

  func complete(with result: TranslationResult) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}

@MainActor
private final class TestLearningStore: LearningStoring {
  private(set) var lastAddition: LearningAddition?
  private var storedItems: [LearningItem]

  init(items: [LearningItem] = []) {
    storedItems = items
  }

  func summary() async throws -> LearningSummary {
    LearningSummary(
      dueCount: 3,
      wordCount: 12,
      sentenceCount: 4
    )
  }

  func add(_ addition: LearningAddition) async throws {
    lastAddition = addition
  }

  func items() async throws -> [LearningItem] {
    storedItems
  }
}

@MainActor
private final class TestApplicationAPIKeyStore: APIKeyStoring {
  private(set) var savedAPIKey: String?

  func loadAPIKey() throws -> String? {
    savedAPIKey
  }

  func saveAPIKey(_ apiKey: String) throws {
    savedAPIKey = apiKey
  }
}

@MainActor
private final class TestTranslationConnectionTester: TranslationConnectionTesting {
  private(set) var lastAPIKey: String?

  func testConnection(apiKey: String) async throws {
    lastAPIKey = apiKey
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

import AppKit
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

  @Test("a captured mouse selection translates with its surrounding context")
  func capturedMouseSelectionTranslatesWithContext() async throws {
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
      environment: .test(translation: translator)
    )
    let snapshot = SelectionSnapshot(
      selectedText: "ran",
      targetSentence: "She ran home.",
      previousSentence: "It was getting late.",
      nextSentence: "Her mother smiled.",
      screenPosition: CGPoint(x: 640, y: 420),
      sourceApplicationName: "Safari"
    )

    await shell.translateSelection(snapshot)

    #expect(
      translator.lastRequest
        == TranslationRequest(
          sourceText: "ran",
          context: """
            Previous sentence:
            It was getting late.

            Target sentence:
            She ran home.

            Next sentence:
            Her mother smiled.
            """,
          kind: .contextualSelection,
          targetSentence: "She ran home."
        ))
    #expect(shell.translationSourceText == "ran")
    #expect(shell.translationDraft?.exampleSentence == "She ran home.")
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

    shell.prepareTranslationPresentation(sourceApplicationName: "Safari")
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
          sourceApplicationName: "Safari",
          createdAt: Date(timeIntervalSince1970: 1_234)
        ))
    #expect(shell.translationDraft == nil)
  }

  @Test("correcting a canonical form to an existing word requires merge confirmation")
  func correctedCanonicalFormRequiresMergeConfirmation() async throws {
    let existingID = UUID(uuidString: "A60B21B0-D9FC-4DBD-B818-A1819310E5E4")!
    let learningStore = TestLearningStore(
      mergeSummary: LearningMergeSummary(
        existingItemID: existingID,
        canonicalForm: "run",
        existingEncounterCount: 2,
        incomingSourceText: "ran"
      ))
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "ran"),
        translation: TestTranslationProvider(
          result: TranslationResult(
            sourceText: "ran",
            canonicalForm: "ran",
            pronunciation: "/ræn/",
            partOfSpeech: "verb",
            contextualMeaning: "跑",
            exampleSentence: "She ran home.",
            sentenceTranslation: "她跑回了家。"
          )),
        learningStore: learningStore
      ))

    await shell.translateClipboard()
    shell.translationDraft?.canonicalForm = "run"
    await shell.addCurrentDraftToLearning()

    #expect(learningStore.lastAddition == nil)
    #expect(
      shell.pendingLearningMerge
        == LearningMergeSummary(
          existingItemID: existingID,
          canonicalForm: "run",
          existingEncounterCount: 2,
          incomingSourceText: "ran"
        ))
    #expect(shell.translationDraft != nil)

    await shell.confirmPendingLearningMerge()

    #expect(learningStore.lastAddition?.draft.canonicalForm == "run")
    #expect(shell.pendingLearningMerge == nil)
    #expect(shell.translationDraft == nil)
  }

  @Test("a successful selected-provider connection saves the API key")
  func successfulSelectedProviderConnectionSavesAPIKey() async {
    let apiKeyStore = TestApplicationAPIKeyStore()
    let connectionTester = TestTranslationConnectionTester()
    let shell = ApplicationShell(
      environment: .test(
        apiKeyStore: apiKeyStore,
        connectionTester: connectionTester
      ))

    await shell.testTranslationConnection(apiKey: "  test-api-key  ")

    #expect(connectionTester.lastAPIKey == "test-api-key")
    #expect(apiKeyStore.savedAPIKeys[.deepSeek] == "test-api-key")
    #expect(shell.connectionStatus == .connected)
  }

  @Test("custom provider settings and API key are saved for the selected provider")
  func customProviderSettingsAndAPIKeyAreSaved() async {
    let configurationStore = TestTranslationProviderConfigurationStore()
    let apiKeyStore = TestApplicationAPIKeyStore()
    let connectionTester = TestTranslationConnectionTester()
    let shell = ApplicationShell(
      environment: .test(
        apiKeyStore: apiKeyStore,
        connectionTester: connectionTester,
        providerConfigurationStore: configurationStore
      ))

    shell.selectTranslationProvider(.openAICompatible)
    shell.updateCustomProvider(
      baseURL: "https://example.com/v1",
      model: "example-model"
    )
    await shell.testTranslationConnection(apiKey: "  custom-api-key  ")

    let expectedConfiguration = TranslationProviderConfiguration(
      provider: .openAICompatible,
      deepSeekModel: .flash,
      customBaseURL: "https://example.com/v1",
      customModel: "example-model"
    )
    #expect(shell.translationProviderConfiguration == expectedConfiguration)
    #expect(configurationStore.savedConfiguration == expectedConfiguration)
    #expect(connectionTester.lastConfiguration == expectedConfiguration)
    #expect(apiKeyStore.savedAPIKeys[.openAICompatible] == "custom-api-key")
    #expect(apiKeyStore.savedAPIKeys[.deepSeek] == nil)
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

  @Test("renaming a library item to an existing word requires merge confirmation")
  func libraryCanonicalCorrectionRequiresMergeConfirmation() async {
    let itemID = UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!
    let existingID = UUID(uuidString: "A60B21B0-D9FC-4DBD-B818-A1819310E5E4")!
    let mergeSummary = LearningMergeSummary(
      existingItemID: existingID,
      canonicalForm: "run",
      existingEncounterCount: 2,
      incomingSourceText: "sprinted"
    )
    let learningStore = TestLearningStore(
      canonicalUpdateResults: [
        .requiresConfirmation(mergeSummary),
        .merged,
      ])
    let shell = ApplicationShell(
      environment: .test(learningStore: learningStore)
    )

    await shell.updateLearningItemCanonicalForm(
      itemID: itemID,
      canonicalForm: "run"
    )

    #expect(
      learningStore.canonicalUpdateInvocations
        == [
          CanonicalUpdateInvocation(
            itemID: itemID,
            canonicalForm: "run",
            confirmMerge: false
          )
        ])
    #expect(shell.pendingLibraryMerge == mergeSummary)

    await shell.confirmPendingLibraryMerge()

    #expect(
      learningStore.canonicalUpdateInvocations
        == [
          CanonicalUpdateInvocation(
            itemID: itemID,
            canonicalForm: "run",
            confirmMerge: false
          ),
          CanonicalUpdateInvocation(
            itemID: itemID,
            canonicalForm: "run",
            confirmMerge: true
          ),
        ])
    #expect(shell.pendingLibraryMerge == nil)
  }

  @Test("rating a due card records the controlled time, reveals the answer, then advances")
  func ratingDueCardRevealsAnswerThenAdvances() async throws {
    let firstItem = makeLearningItem(
      id: UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!,
      canonicalForm: "run"
    )
    let secondItem = makeLearningItem(
      id: UUID(uuidString: "A60B21B0-D9FC-4DBD-B818-A1819310E5E4")!,
      canonicalForm: "pause"
    )
    let learningStore = TestLearningStore(dueItems: [firstItem, secondItem])
    let shell = ApplicationShell(
      environment: .test(learningStore: learningStore)
    )

    await shell.refreshTodayReview()

    #expect(shell.currentReviewItem == firstItem)
    #expect(shell.isReviewAnswerVisible == false)
    #expect(shell.selectedReviewRating == nil)

    await shell.rateCurrentReview(.remembered)

    #expect(
      learningStore.reviewInvocations
        == [
          ReviewInvocation(
            itemID: firstItem.id,
            rating: .remembered,
            reviewedAt: Date(timeIntervalSince1970: 1_234)
          )
        ])
    #expect(shell.currentReviewItem == firstItem)
    #expect(shell.isReviewAnswerVisible)
    #expect(shell.selectedReviewRating == .remembered)

    shell.advanceToNextReview()

    #expect(shell.currentReviewItem == secondItem)
    #expect(shell.isReviewAnswerVisible == false)
    #expect(shell.selectedReviewRating == nil)
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

  private func makeLearningItem(id: UUID, canonicalForm: String) -> LearningItem {
    LearningItem(
      id: id,
      sourceText: canonicalForm,
      canonicalForm: canonicalForm,
      pronunciation: "",
      partOfSpeech: "verb",
      contextualMeaning: canonicalForm,
      exampleSentence: "\(canonicalForm) example",
      sentenceTranslation: "\(canonicalForm) 翻译",
      sourceApplicationName: "Safari",
      createdAt: Date(timeIntervalSince1970: 1_000),
      nextReviewAt: Date(timeIntervalSince1970: 1_200)
    )
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

  @Test("translation panel floats without activating TranStudy")
  func translationPanelDoesNotActivateApplication() async {
    let shell = ApplicationShell(environment: .test())
    let controller = TranslationPanelController(shell: shell)
    NSApp.deactivate()
    try? await Task.sleep(for: .milliseconds(100))
    #expect(NSApp.isActive == false)

    controller.presentClipboardTranslation()
    try? await Task.sleep(for: .milliseconds(100))

    let panel = NSApp.windows
      .compactMap { $0 as? NSPanel }
      .first { $0.delegate === controller }

    #expect(NSApp.isActive == false)
    #expect(panel?.styleMask.contains(.nonactivatingPanel) == true)
    #expect(panel?.hidesOnDeactivate == false)
    controller.dismiss()
  }

  @Test("translation panel uses the position selected in settings")
  func translationPanelUsesSelectedPosition() throws {
    let positionStore = TestTranslationPanelPositionStore(position: .topTrailing)
    let shell = ApplicationShell(
      environment: .test(panelPositionStore: positionStore)
    )
    let controller = TranslationPanelController(shell: shell)
    let screen = try #require(NSScreen.main)

    shell.setTranslationPanelPosition(.topLeading)
    controller.presentClipboardTranslation()

    let panel = try #require(
      NSApp.windows
        .compactMap { $0 as? NSPanel }
        .first { $0.delegate === controller }
    )
    let expectedOrigin = TranslationPanelPosition.topLeading.origin(
      panelSize: panel.frame.size,
      visibleFrame: screen.visibleFrame
    )

    #expect(positionStore.savedPosition == .topLeading)
    #expect(panel.frame.origin == expectedOrigin)
    controller.dismiss()
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
    notifier: TestReviewNotifier = TestReviewNotifier(),
    panelPositionStore: TestTranslationPanelPositionStore = TestTranslationPanelPositionStore(),
    providerConfigurationStore: TestTranslationProviderConfigurationStore =
      TestTranslationProviderConfigurationStore(),
    selectionConfigurationStore: TestSelectionConfigurationStore =
      TestSelectionConfigurationStore()
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
      speech: TestSpeechPlayer(),
      panelPositionStore: panelPositionStore,
      providerConfigurationStore: providerConfigurationStore,
      selectionConfigurationStore: selectionConfigurationStore
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
  private(set) var canonicalUpdateInvocations: [CanonicalUpdateInvocation] = []
  private(set) var reviewInvocations: [ReviewInvocation] = []
  private var storedItems: [LearningItem]
  private var storedDueItems: [LearningItem]
  private let storedMergeSummary: LearningMergeSummary?
  private var canonicalUpdateResults: [LearningCanonicalUpdateResult]

  init(
    items: [LearningItem] = [],
    dueItems: [LearningItem] = [],
    mergeSummary: LearningMergeSummary? = nil,
    canonicalUpdateResults: [LearningCanonicalUpdateResult] = []
  ) {
    storedItems = items
    storedDueItems = dueItems
    storedMergeSummary = mergeSummary
    self.canonicalUpdateResults = canonicalUpdateResults
  }

  func summary(at date: Date) async throws -> LearningSummary {
    LearningSummary(
      dueCount: 3,
      wordCount: 12,
      sentenceCount: 4
    )
  }

  func add(_ addition: LearningAddition) async throws {
    lastAddition = addition
  }

  func dueItems(at date: Date) async throws -> [LearningItem] {
    storedDueItems
  }

  func recordReview(
    itemID: UUID,
    rating: ReviewRating,
    reviewedAt: Date
  ) async throws -> LearningReviewResult {
    reviewInvocations.append(
      ReviewInvocation(
        itemID: itemID,
        rating: rating,
        reviewedAt: reviewedAt
      ))
    return LearningReviewResult(
      itemID: itemID,
      rating: rating,
      reviewedAt: reviewedAt,
      nextReviewAt: reviewedAt.addingTimeInterval(3 * 86_400),
      intervalDays: 3
    )
  }

  func mergeSummary(for addition: LearningAddition) async throws -> LearningMergeSummary? {
    storedMergeSummary
  }

  func updateCanonicalForm(
    itemID: UUID,
    canonicalForm: String,
    confirmMerge: Bool
  ) async throws -> LearningCanonicalUpdateResult {
    canonicalUpdateInvocations.append(
      CanonicalUpdateInvocation(
        itemID: itemID,
        canonicalForm: canonicalForm,
        confirmMerge: confirmMerge
      ))
    return canonicalUpdateResults.isEmpty ? .updated : canonicalUpdateResults.removeFirst()
  }

  func items() async throws -> [LearningItem] {
    storedItems
  }
}

private struct CanonicalUpdateInvocation: Equatable {
  let itemID: UUID
  let canonicalForm: String
  let confirmMerge: Bool
}

private struct ReviewInvocation: Equatable {
  let itemID: UUID
  let rating: ReviewRating
  let reviewedAt: Date
}

@MainActor
private final class TestApplicationAPIKeyStore: APIKeyStoring {
  private(set) var savedAPIKeys: [TranslationProviderKind: String] = [:]

  func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
    savedAPIKeys[provider]
  }

  func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {
    savedAPIKeys[provider] = apiKey
  }
}

@MainActor
private final class TestTranslationConnectionTester: TranslationConnectionTesting {
  private(set) var lastAPIKey: String?
  private(set) var lastConfiguration: TranslationProviderConfiguration?

  func testConnection(
    configuration: TranslationProviderConfiguration,
    apiKey: String
  ) async throws {
    lastConfiguration = configuration
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

private final class TestTranslationPanelPositionStore: TranslationPanelPositionStoring {
  private(set) var savedPosition: TranslationPanelPosition

  init(position: TranslationPanelPosition = .topTrailing) {
    savedPosition = position
  }

  func load() -> TranslationPanelPosition {
    savedPosition
  }

  func save(_ position: TranslationPanelPosition) {
    savedPosition = position
  }
}

private final class TestTranslationProviderConfigurationStore:
  TranslationProviderConfigurationStoring
{
  private(set) var savedConfiguration: TranslationProviderConfiguration

  init(configuration: TranslationProviderConfiguration = .default) {
    savedConfiguration = configuration
  }

  func load() -> TranslationProviderConfiguration {
    savedConfiguration
  }

  func save(_ configuration: TranslationProviderConfiguration) {
    savedConfiguration = configuration
  }
}

private final class TestSelectionConfigurationStore: SelectionConfigurationStoring {
  private(set) var savedConfiguration: SelectionConfiguration

  init(configuration: SelectionConfiguration = .default) {
    savedConfiguration = configuration
  }

  func load() -> SelectionConfiguration {
    savedConfiguration
  }

  func save(_ configuration: SelectionConfiguration) {
    savedConfiguration = configuration
  }
}

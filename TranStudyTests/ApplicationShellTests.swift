import AppKit
import Foundation
import Testing

@testable import TranStudy

@MainActor
struct ApplicationShellTests {
  @Test("update checks stay user-controlled and manual checks require availability")
  func updateChecksStayUserControlled() {
    let updates = TestUpdateChecker()
    let shell = ApplicationShell(
      environment: .test(updates: updates)
    )

    #expect(!shell.automaticallyChecksForUpdates)

    shell.setAutomaticallyChecksForUpdates(true)
    #expect(shell.automaticallyChecksForUpdates)
    #expect(updates.automaticallyChecksForUpdates)

    shell.checkForUpdates()
    #expect(updates.checkCount == 1)

    updates.canCheckForUpdates = false
    shell.checkForUpdates()
    #expect(updates.checkCount == 1)
  }

  @Test("writing system is persisted and attached to new translation requests")
  func writingSystemPersistsAndAppliesToNewTranslations() async throws {
    let preferencesStore = TestLanguageAndSpeechPreferencesStore()
    let translator = TestTranslationProvider(
      result: TranslationResult(
        sourceText: "resilient",
        canonicalForm: "resilient",
        pronunciation: "/rɪˈzɪliənt/",
        partOfSpeech: "adjective",
        contextualMeaning: "有韌性的",
        exampleSentence: "The team remained resilient.",
        sentenceTranslation: "團隊依然保持韌性。"
      ))
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "resilient"),
        translation: translator,
        languageAndSpeechPreferencesStore: preferencesStore
      ))

    shell.setChineseWritingSystem(.traditional)
    await shell.translateClipboard()

    #expect(preferencesStore.preferences.chineseWritingSystem == .traditional)
    #expect(translator.lastRequest?.chineseWritingSystem == .traditional)
  }

  @Test("automatic speech remains off until enabled and uses saved voice settings")
  func automaticSpeechUsesSavedVoiceSettings() async throws {
    let speech = TestSpeechPlayer()
    let translator = TestTranslationProvider(
      result: TranslationResult(
        sourceText: "resilient",
        canonicalForm: "resilient",
        pronunciation: "/rɪˈzɪliənt/",
        partOfSpeech: "adjective",
        contextualMeaning: "有韧性的",
        exampleSentence: "The team remained resilient.",
        sentenceTranslation: "团队依然保持韧性。"
      ))
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "resilient"),
        translation: translator,
        speech: speech
      ))

    await shell.translateClipboard()
    #expect(speech.spokenItems.isEmpty)

    shell.setSpeechVoiceIdentifier("voice.en-US")
    shell.setSpeechRate(0.6)
    shell.setAutomaticallySpeaksTranslations(true)
    await shell.translateClipboard()

    #expect(
      speech.spokenItems
        == [
          .init(
            text: "resilient",
            voiceIdentifier: "voice.en-US",
            rate: 0.6
          )
        ]
    )
  }

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

  @Test("translated examples collapse line breaks before becoming a draft")
  func translatedExamplesCollapseLineBreaksBeforeBecomingDraft() async {
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: "resilient"),
        translation: TestTranslationProvider(
          result: TranslationResult(
            sourceText: "resilient",
            canonicalForm: "resilient",
            pronunciation: "/rɪˈzɪliənt/",
            partOfSpeech: "adjective",
            contextualMeaning: "有韧性的",
            exampleSentence: "The team remained resilient\nafter the setback.",
            sentenceTranslation: "团队在挫折后\n依然保持韧性。"
          ))
      ))

    await shell.translateClipboard()

    #expect(
      shell.translationDraft?.exampleSentence
        == "The team remained resilient after the setback."
    )
    #expect(shell.translationDraft?.sentenceTranslation == "团队在挫折后 依然保持韧性。")
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

  @Test("a selection without sentence context never starts translation")
  func selectionWithoutSentenceContextNeverStartsTranslation() async {
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
      targetSentence: nil,
      previousSentence: nil,
      nextSentence: nil,
      screenPosition: CGPoint(x: 640, y: 420),
      sourceApplicationName: "Unsupported Reader"
    )

    await shell.translateSelection(snapshot)

    #expect(translator.lastRequest == nil)
    #expect(shell.translationDraft == nil)
    #expect(shell.translationStatus == .failed)
  }

  @Test("selection pause and application exclusions persist immediately")
  func selectionPrivacySettingsPersistImmediately() {
    let configurationStore = TestSelectionConfigurationStore()
    let shell = ApplicationShell(
      environment: .test(selectionConfigurationStore: configurationStore)
    )

    shell.setSelectionEnabled(false)
    shell.excludeApplication(
      bundleIdentifier: " com.example.Reader ",
      displayName: " Reader "
    )
    shell.excludeApplication(
      bundleIdentifier: "COM.EXAMPLE.READER",
      displayName: "Duplicate"
    )

    #expect(
      configurationStore.savedConfiguration
        == SelectionConfiguration(
          isEnabled: false,
          excludedApplications: [
            ExcludedApplication(
              bundleIdentifier: "com.example.Reader",
              displayName: "Reader"
            )
          ]
        ))

    shell.includeApplication(bundleIdentifier: "COM.EXAMPLE.READER")

    #expect(configurationStore.savedConfiguration.excludedApplications.isEmpty)
  }

  @Test("sentence card capability is opt-in and persists immediately")
  func sentenceCardCapabilityIsOptIn() {
    let configurationStore = TestSentenceCardConfigurationStore()
    let shell = ApplicationShell(
      environment: .test(sentenceCardConfigurationStore: configurationStore)
    )

    #expect(!shell.isSentenceCardsEnabled)

    shell.setSentenceCardsEnabled(true)

    #expect(shell.isSentenceCardsEnabled)
    #expect(configurationStore.savedValue)
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
    #expect(shell.isTranslationServiceConfigured)
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

  @Test("library selection can select all, archive, and restore cards")
  func librarySelectionArchivesAndRestoresCards() async {
    let firstItem = makeLearningItem(
      id: UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!,
      canonicalForm: "run"
    )
    let secondItem = makeLearningItem(
      id: UUID(uuidString: "A60B21B0-D9FC-4DBD-B818-A1819310E5E4")!,
      canonicalForm: "pause"
    )
    let learningStore = TestLearningStore(items: [firstItem, secondItem])
    let shell = ApplicationShell(
      environment: .test(learningStore: learningStore)
    )
    await shell.refreshLibrary()

    shell.beginLibrarySelection()
    shell.toggleLibrarySelection(firstItem.id)
    #expect(shell.selectedLearningItemIDs == [firstItem.id])

    shell.selectAllLibraryItems()
    #expect(shell.selectedLearningItemIDs == [firstItem.id, secondItem.id])

    await shell.archiveSelectedLibraryItems()

    #expect(shell.learningItems.isEmpty)
    #expect(Set(shell.archivedLearningItems.map(\.id)) == [firstItem.id, secondItem.id])
    #expect(!shell.isLibrarySelecting)

    shell.setLibraryScope(.archived)
    shell.beginLibrarySelection()
    shell.selectAllLibraryItems()
    await shell.restoreSelectedLibraryItems()

    #expect(Set(shell.learningItems.map(\.id)) == [firstItem.id, secondItem.id])
    #expect(shell.archivedLearningItems.isEmpty)
  }

  @Test("a pending library deletion can be undone before persistence")
  func pendingLibraryDeletionCanBeUndone() async {
    let (item, learningStore, shell) = await makeLibraryDeletionContext()

    let didStage = await shell.stageLibraryItemDeletion(itemID: item.id)

    #expect(didStage)
    #expect(shell.pendingLibraryDeletion == item)
    #expect(shell.displayedLearningItems.isEmpty)
    #expect(shell.learningItems.isEmpty)

    await shell.undoLibraryItemDeletion()

    #expect(shell.pendingLibraryDeletion == nil)
    #expect(shell.displayedLearningItems == [item])
    #expect(learningStore.deletedItemIDs.isEmpty)
  }

  @Test("finalizing a pending library deletion permanently removes the card")
  func finalizingPendingLibraryDeletionPersistsRemoval() async {
    let (item, learningStore, shell) = await makeLibraryDeletionContext()
    let didStage = await shell.stageLibraryItemDeletion(itemID: item.id)
    #expect(didStage)

    await shell.finalizeLibraryItemDeletion(itemID: item.id)

    #expect(learningStore.deletedItemIDs == [item.id])
    #expect(shell.pendingLibraryDeletion == nil)
    #expect(shell.learningItems.isEmpty)
  }

  @Test("refreshing the library resumes a persisted pending deletion")
  func refreshingLibraryResumesPersistedDeletion() async {
    let item = makeLearningItem(
      id: UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!,
      canonicalForm: "run"
    )
    let deletion = PendingLearningDeletion(
      item: item,
      deleteAt: Date(timeIntervalSince1970: 1_244)
    )
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(pendingDeletion: deletion)
      ))

    await shell.refreshLibrary()

    #expect(shell.pendingLibraryDeletion == item)
    #expect(shell.learningItems.isEmpty)
  }

  @Test("library search covers word forms and examples within the current scope")
  func librarySearchFiltersCurrentScope() async {
    let runID = UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!
    let pauseID = UUID(uuidString: "A60B21B0-D9FC-4DBD-B818-A1819310E5E4")!
    let archivedID = UUID(uuidString: "FCB9085D-879A-44A5-8B23-B9B972DFC714")!
    let runItem = LearningItem(
      id: runID,
      sourceText: "sprinted",
      canonicalForm: "run",
      pronunciation: "/rʌn/",
      partOfSpeech: "verb",
      contextualMeaning: "奔跑",
      exampleSentence: "She runs every morning.",
      sentenceTranslation: "她每天早上跑步。",
      sourceApplicationName: "Safari",
      createdAt: Date(timeIntervalSince1970: 1_000),
      encounters: [
        LearningEncounter(
          id: UUID(),
          sourceText: "ran",
          pronunciation: "/ræn/",
          partOfSpeech: "verb",
          contextualMeaning: "跑",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她跑回了家。",
          sourceApplicationName: "TextEdit",
          encounteredAt: Date(timeIntervalSince1970: 900)
        )
      ],
      customExamples: [
        LearningCustomExample(
          englishText: "They run a small café.",
          chineseTranslation: "他们经营一家小咖啡馆。"
        )
      ]
    )
    let pauseItem = makeLearningItem(id: pauseID, canonicalForm: "pause")
    let archivedItem = LearningItem(
      id: archivedID,
      sourceText: "archived",
      canonicalForm: "archive",
      pronunciation: "",
      partOfSpeech: "verb",
      contextualMeaning: "归档",
      exampleSentence: "Archive this card.",
      sentenceTranslation: "归档这张卡。",
      sourceApplicationName: "Preview",
      createdAt: Date(timeIntervalSince1970: 800),
      archivedAt: Date(timeIntervalSince1970: 1_200)
    )
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(
          items: [runItem, pauseItem],
          archivedItems: [archivedItem]
        )
      ))
    await shell.refreshLibrary()

    shell.librarySearchQuery = "SPRINTED"
    #expect(shell.displayedLearningItems.map(\.id) == [runID])

    shell.librarySearchQuery = "ran home"
    #expect(shell.displayedLearningItems.map(\.id) == [runID])

    shell.librarySearchQuery = "small café"
    #expect(shell.displayedLearningItems.map(\.id) == [runID])

    shell.beginLibrarySelection()
    shell.selectAllLibraryItems()
    #expect(shell.selectedLearningItemIDs == [runID])

    shell.setLibraryScope(.archived)
    shell.librarySearchQuery = "archive this"
    #expect(shell.displayedLearningItems.map(\.id) == [archivedID])
  }

  @Test("failed library detail save remains unsuccessful")
  func failedLibraryDetailSaveRemainsUnsuccessful() async {
    let item = makeLearningItem(
      id: UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!,
      canonicalForm: "run"
    )
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(
          items: [item],
          detailsUpdateError: TestLearningStoreError.updateFailed
        )
      ))

    let didSave = await shell.saveLearningItem(
      itemID: item.id,
      canonicalForm: "run",
      details: LearningItemDetailsUpdate(
        pronunciation: "/rʌn/",
        partOfSpeech: "verb",
        contextualMeaning: "奔跑",
        exampleSentence: "I run daily.",
        sentenceTranslation: "我每天跑步。",
        userNote: "测试",
        customExamples: []
      )
    )

    #expect(!didSave)
  }

  @Test("setting a library item's next review date persists the selected date")
  func settingLibraryItemNextReviewDatePersistsSelectedDate() async {
    let itemID = UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!
    let nextReviewAt = Date(timeIntervalSince1970: 20_000)
    let learningStore = TestLearningStore()
    let shell = ApplicationShell(
      environment: .test(learningStore: learningStore)
    )

    let didUpdate = await shell.setLearningItemNextReviewDate(
      itemID: itemID,
      nextReviewAt: nextReviewAt
    )

    #expect(didUpdate)
    #expect(
      learningStore.nextReviewDateInvocations
        == [NextReviewDateInvocation(itemID: itemID, nextReviewAt: nextReviewAt)]
    )
  }

  @Test("pausing and resuming a library item persist the requested state")
  func pausingAndResumingLibraryItemPersistRequestedState() async {
    let itemID = UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!
    let learningStore = TestLearningStore()
    let shell = ApplicationShell(
      environment: .test(learningStore: learningStore)
    )

    let didPause = await shell.setLearningItemReviewPaused(
      itemID: itemID,
      isPaused: true
    )
    let didResume = await shell.setLearningItemReviewPaused(
      itemID: itemID,
      isPaused: false
    )

    #expect(didPause)
    #expect(didResume)
    #expect(
      learningStore.reviewPausedInvocations
        == [
          ReviewPausedInvocation(itemID: itemID, isPaused: true),
          ReviewPausedInvocation(itemID: itemID, isPaused: false),
        ])
  }

  @Test("resetting a library item uses the controlled current time")
  func resettingLibraryItemUsesControlledCurrentTime() async {
    let itemID = UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!
    let learningStore = TestLearningStore()
    let shell = ApplicationShell(
      environment: .test(learningStore: learningStore)
    )

    let resetAt = await shell.resetLearningItemReviewProgress(itemID: itemID)

    #expect(resetAt == Date(timeIntervalSince1970: 1_234))
    #expect(
      learningStore.reviewResetInvocations
        == [
          ReviewResetInvocation(
            itemID: itemID,
            resetAt: Date(timeIntervalSince1970: 1_234)
          )
        ])
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
      canonicalForm: "run",
      nextReviewAt: Date(timeIntervalSince1970: -100)
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

  @Test("daily review advances through complete twenty-card batches")
  func dailyReviewUsesTwentyCardBatches() async {
    let dueItems = (0..<45).map { index in
      makeLearningItem(
        id: UUID(),
        canonicalForm: "word-\(index)",
        nextReviewAt: Date(timeIntervalSince1970: 1_200)
      )
    }
    let learningStore = TestLearningStore(
      summary: LearningSummary(
        dueCount: 45,
        wordCount: 45,
        sentenceCount: 0
      ),
      dueItems: dueItems
    )
    let shell = ApplicationShell(
      environment: .test(learningStore: learningStore)
    )

    await shell.refreshTodayReview()

    #expect(shell.reviewQueue.count == 20)
    #expect(shell.remainingReviewCount == 25)
    #expect(shell.hasMoreReviewBatches)

    while shell.currentReviewItem != nil {
      await shell.rateCurrentReview(.remembered)
      shell.advanceToNextReview()
    }

    #expect(learningStore.reviewInvocations.count == 20)
    #expect(shell.hasMoreReviewBatches)

    shell.startNextReviewBatch()

    #expect(shell.reviewQueue.count == 20)
    #expect(shell.remainingReviewCount == 5)
    #expect(
      Set(shell.reviewQueue.map(\.id))
        .isDisjoint(with: Set(learningStore.reviewInvocations.map(\.itemID)))
    )
  }

  @Test("the daily reminder uses the real due count at delivery time")
  func dailyReminderUsesTheRealDueCount() async throws {
    let dueItems = [
      makeLearningItem(id: UUID(), canonicalForm: "run"),
      makeLearningItem(id: UUID(), canonicalForm: "pause"),
    ]
    let notifier = TestReviewNotifier()
    let reminderStore = TestReviewReminderConfigurationStore(
      configuration: ReviewReminderConfiguration(
        isEnabled: true,
        hour: 9,
        minute: 15
      ))
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(
          summary: LearningSummary(
            dueCount: 2,
            wordCount: 2,
            sentenceCount: 0
          ),
          dueItems: dueItems
        ),
        notifier: notifier,
        reminderConfigurationStore: reminderStore
      ))

    await shell.sendReviewReminderIfNeeded()

    let reminder = try #require(notifier.lastReminder)
    #expect(reminder.dueCount == 2)
  }

  @Test("reminders are removed when no cards are due")
  func remindersAreRemovedWhenNoCardsAreDue() async {
    let notifier = TestReviewNotifier()
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(
          summary: LearningSummary(
            dueCount: 0,
            wordCount: 2,
            sentenceCount: 0
          )
        ),
        notifier: notifier,
        reminderConfigurationStore: TestReviewReminderConfigurationStore(
          configuration: ReviewReminderConfiguration(
            isEnabled: true,
            hour: 9,
            minute: 15
          ))
      ))

    await shell.sendReviewReminderIfNeeded()

    #expect(notifier.receivedReminders.count == 1)
    #expect(notifier.receivedReminders[0] == nil)
  }

  @Test("notification scheduling failure does not block today's review")
  func notificationSchedulingFailureDoesNotBlockReview() async {
    let dueItem = makeLearningItem(id: UUID(), canonicalForm: "run")
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(
          summary: LearningSummary(
            dueCount: 1,
            wordCount: 1,
            sentenceCount: 0
          ),
          dueItems: [dueItem]
        ),
        notifier: TestReviewNotifier(error: TestReviewNotifierError.denied),
        reminderConfigurationStore: TestReviewReminderConfigurationStore(
          configuration: ReviewReminderConfiguration(
            isEnabled: true,
            hour: 9,
            minute: 15
          ))
      ))

    await shell.refreshTodayReview()
    await shell.sendReviewReminderIfNeeded()

    #expect(shell.currentReviewItem == dueItem)
    #expect(shell.learningSummary.dueCount == 1)
  }

  @Test("finishing the final due card removes its pending reminder")
  func finishingFinalDueCardRemovesPendingReminder() async {
    let dueItem = makeLearningItem(id: UUID(), canonicalForm: "run")
    let notifier = TestReviewNotifier()
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(
          summary: LearningSummary(
            dueCount: 1,
            wordCount: 1,
            sentenceCount: 0
          ),
          dueItems: [dueItem]
        ),
        notifier: notifier,
        reminderConfigurationStore: TestReviewReminderConfigurationStore(
          configuration: ReviewReminderConfiguration(
            isEnabled: true,
            hour: 9,
            minute: 15
          ))
      ))
    await shell.refreshTodayReview()
    await shell.sendReviewReminderIfNeeded()

    await shell.rateCurrentReview(.remembered)

    #expect(notifier.receivedReminders.count == 2)
    #expect(notifier.receivedReminders[0]?.dueCount == 1)
    #expect(notifier.receivedReminders[1] == nil)
  }

  @Test("reminder settings persist and restart the daily monitor")
  func reminderSettingsPersistAndRestartMonitor() async {
    let reminderStore = TestReviewReminderConfigurationStore()
    let shell = ApplicationShell(
      environment: .test(
        reminderConfigurationStore: reminderStore
      ))
    var configurationChangeCount = 0
    shell.onReviewReminderConfigurationChange = {
      configurationChangeCount += 1
    }

    await shell.setReviewReminderEnabled(true)
    await shell.setReviewReminderTime(hour: 18, minute: 30)

    #expect(
      reminderStore.savedConfiguration
        == ReviewReminderConfiguration(
          isEnabled: true,
          hour: 18,
          minute: 30
        ))
    #expect(configurationChangeCount == 2)
  }

  @Test("starting review selects today and refreshes the due cards")
  func startingReviewSelectsTodayAndRefreshesDueCards() async {
    let dueItem = makeLearningItem(id: UUID(), canonicalForm: "run")
    let shell = ApplicationShell(
      environment: .test(
        learningStore: TestLearningStore(dueItems: [dueItem])
      ))
    shell.selectedDestination = .library

    await shell.startTodayReview()

    #expect(shell.selectedDestination == .todayReview)
    #expect(shell.currentReviewItem == dueItem)
  }

  @Test("launch at login is opt-in and follows the system registration")
  func launchAtLoginIsOptIn() {
    let loginItem = TestLoginItemController()
    let shell = ApplicationShell(
      environment: .test(loginItem: loginItem)
    )

    #expect(!shell.isLaunchAtLoginEnabled)

    shell.setLaunchAtLoginEnabled(true)

    #expect(shell.isLaunchAtLoginEnabled)
    #expect(loginItem.isEnabled)
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

  private func makeLearningItem(
    id: UUID,
    canonicalForm: String,
    nextReviewAt: Date = Date(timeIntervalSince1970: 1_200)
  ) -> LearningItem {
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
      nextReviewAt: nextReviewAt
    )
  }

  private func makeLibraryDeletionContext() async -> (
    item: LearningItem,
    store: TestLearningStore,
    shell: ApplicationShell
  ) {
    let item = makeLearningItem(
      id: UUID(uuidString: "7A9589F8-62AE-4F8A-87B2-72775B331759")!,
      canonicalForm: "run"
    )
    let store = TestLearningStore(items: [item])
    let shell = ApplicationShell(
      environment: .test(learningStore: store)
    )
    await shell.refreshLibrary()
    return (item, store, shell)
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

  @Test("long clipboard text collapses line breaks before contextual word selection")
  func longClipboardTextCollapsesLineBreaksBeforeContextualWordSelection() async {
    let source = """
      In a realistic program, convention dictates that
        if any method of
        Point has a pointer receiver, then all methods of Point
        should have a pointer receiver, even ones that don’t strictly need it.

        We’ve broken this rule for Point so that we can show
      """
    let expectedSentence =
      "In a realistic program, convention dictates that if any method of Point has a pointer receiver, then all methods of Point should have a pointer receiver, even ones that don’t strictly need it."
    let expectedSource =
      "\(expectedSentence) We’ve broken this rule for Point so that we can show"
    let translator = TestLongTextTranslationProvider()
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: source),
        translation: translator
      ))

    await shell.translateClipboard()

    let selectedRange = (expectedSentence as NSString).range(of: "convention")
    await shell.translateLongTextSelection(selectedRange)

    #expect(translator.lastLongTextSource == expectedSource)
    #expect(translator.lastRequest?.sourceText == "convention")
    #expect(translator.lastRequest?.targetSentence == expectedSentence)
  }

  @Test("enabled sentence cards are added only after the explicit sentence action")
  func sentenceCardsRequireExplicitLongTextAction() async {
    let source = "She ran home. They stayed outside."
    let sentence = "She ran home."
    let selectedRange = (source as NSString).range(of: "ran")
    let translator = SentenceCardTranslationProvider(
      translations: [
        source: "她跑回了家。他们待在外面。",
        sentence: "她跑回了家。",
      ])
    let learningStore = TestLearningStore()
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: source),
        translation: translator,
        learningStore: learningStore,
        sentenceCardConfigurationStore: TestSentenceCardConfigurationStore(
          isEnabled: true
        )
      ))

    await shell.translateClipboard()

    #expect(learningStore.lastAddition == nil)
    #expect(shell.canAddLongTextSentence(selectedRange))

    await shell.addLongTextSentence(selectedRange)

    #expect(translator.translatedSources == [source, sentence])
    #expect(
      learningStore.lastAddition
        == LearningAddition(
          kind: .sentence,
          draft: TranslationDraft(
            sourceText: sentence,
            canonicalForm: sentence,
            pronunciation: "",
            partOfSpeech: "",
            contextualMeaning: "",
            exampleSentence: sentence,
            sentenceTranslation: "她跑回了家。"
          ),
          sourceApplicationName: "剪贴板",
          createdAt: Date(timeIntervalSince1970: 1_234)
        ))
    #expect(shell.sentenceCardAdditionStatus == .added)

    shell.clearSentenceCardAdditionStatus()

    #expect(shell.sentenceCardAdditionStatus == nil)
  }

  @Test("sentence cards reject a selection that crosses sentence boundaries")
  func sentenceCardsRejectCrossSentenceSelection() async {
    let source = "She ran home. They stayed outside."
    let selectedRange = (source as NSString).range(of: "home. They")
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: source),
        translation: SentenceCardTranslationProvider(
          translations: [source: "她跑回了家。他们待在外面。"]
        ),
        sentenceCardConfigurationStore: TestSentenceCardConfigurationStore(
          isEnabled: true
        )
      ))

    await shell.translateClipboard()

    #expect(!shell.canAddLongTextSentence(selectedRange))
  }

  @Test("sentence card addition exposes translation failure")
  func sentenceCardAdditionExposesTranslationFailure() async {
    let source = "She ran home. They stayed outside."
    let selectedRange = (source as NSString).range(of: "ran")
    let shell = ApplicationShell(
      environment: .test(
        clipboard: TestClipboardReader(text: source),
        translation: SentenceCardTranslationProvider(
          translations: [source: "她跑回了家。他们待在外面。"]
        ),
        sentenceCardConfigurationStore: TestSentenceCardConfigurationStore(
          isEnabled: true
        )
      ))

    await shell.translateClipboard()
    await shell.addLongTextSentence(selectedRange)

    #expect(shell.sentenceCardAdditionStatus == .failed)
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

  @Test("first preparation flow is shown once and completion persists")
  func firstPreparationFlowIsShownOnce() {
    let preparationStore = TestPreparationStateStore()
    let firstShell = ApplicationShell(
      environment: .test(preparationStateStore: preparationStore)
    )

    #expect(firstShell.isPreparationPresented)

    firstShell.completeInitialPreparation()

    #expect(!firstShell.isPreparationPresented)
    #expect(preparationStore.hasCompletedInitialFlow)

    let relaunchedShell = ApplicationShell(
      environment: .test(preparationStateStore: preparationStore)
    )

    #expect(!relaunchedShell.isPreparationPresented)
  }

  @Test("preparation status reflects replaceable system capabilities")
  func preparationStatusReflectsSystemCapabilities() async {
    let accessibility = TestAccessibilityAuthorizer(status: .denied)
    let notifier = TestReviewNotifier(authorizationStatus: .authorized)
    let apiKeyStore = TestApplicationAPIKeyStore(apiKey: "saved-key")
    let shell = ApplicationShell(
      environment: .test(
        apiKeyStore: apiKeyStore,
        notifier: notifier,
        accessibility: accessibility
      )
    )

    await shell.refreshPreparationStatus()

    #expect(shell.accessibilityAuthorizationStatus == .denied)
    #expect(shell.notificationAuthorizationStatus == .authorized)
    #expect(shell.isTranslationServiceConfigured)
    #expect(shell.missingPreparationCapabilities == [.accessibility])
  }

  @Test("optional permission requests do not gate the main application")
  func optionalPermissionRequestsDoNotGateMainApplication() async {
    let accessibility = TestAccessibilityAuthorizer(status: .denied)
    let notifier = TestReviewNotifier(
      authorizationStatus: .notDetermined,
      authorizationRequestResult: false
    )
    let shell = ApplicationShell(
      environment: .test(
        notifier: notifier,
        accessibility: accessibility
      )
    )

    shell.requestAccessibilityAuthorization()
    await shell.requestNotificationAuthorization()
    shell.completeInitialPreparation()

    #expect(accessibility.didRequestAuthorization)
    #expect(notifier.didRequestAuthorization)
    #expect(shell.accessibilityAuthorizationStatus == .denied)
    #expect(shell.notificationAuthorizationStatus == .denied)
    #expect(!shell.isPreparationPresented)
    #expect(shell.selectedDestination == .todayReview)
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
    accessibility: TestAccessibilityAuthorizer = TestAccessibilityAuthorizer(),
    reminderConfigurationStore: TestReviewReminderConfigurationStore =
      TestReviewReminderConfigurationStore(),
    loginItem: TestLoginItemController = TestLoginItemController(),
    updates: TestUpdateChecker = TestUpdateChecker(),
    speech: any SpeechPlaying = TestSpeechPlayer(),
    languageAndSpeechPreferencesStore: TestLanguageAndSpeechPreferencesStore =
      TestLanguageAndSpeechPreferencesStore(),
    panelPositionStore: TestTranslationPanelPositionStore = TestTranslationPanelPositionStore(),
    providerConfigurationStore: TestTranslationProviderConfigurationStore =
      TestTranslationProviderConfigurationStore(),
    selectionConfigurationStore: TestSelectionConfigurationStore =
      TestSelectionConfigurationStore(),
    shortcutStore: TestTranslationShortcutStore = TestTranslationShortcutStore(),
    sentenceCardConfigurationStore: TestSentenceCardConfigurationStore =
      TestSentenceCardConfigurationStore(),
    preparationStateStore: TestPreparationStateStore = TestPreparationStateStore()
  ) -> ApplicationEnvironment {
    ApplicationEnvironment(
      selection: TestSelectionProvider(),
      clipboard: clipboard,
      translation: translation,
      translationCache: InMemoryTranslationCacheStore(),
      diagnostics: TestDiagnosticLogger(),
      learningStore: learningStore,
      apiKeyStore: apiKeyStore,
      connectionTester: connectionTester,
      clock: TestClock(),
      notifications: notifier,
      accessibilityAuthorization: accessibility,
      reviewReminderConfigurationStore: reminderConfigurationStore,
      loginItem: loginItem,
      updates: updates,
      speech: speech,
      languageAndSpeechPreferencesStore: languageAndSpeechPreferencesStore,
      panelPositionStore: panelPositionStore,
      providerConfigurationStore: providerConfigurationStore,
      selectionConfigurationStore: selectionConfigurationStore,
      shortcutStore: shortcutStore,
      sentenceCardConfigurationStore: sentenceCardConfigurationStore,
      preparationStateStore: preparationStateStore
    )
  }
}

@MainActor
private final class TestUpdateChecker: UpdateChecking {
  var automaticallyChecksForUpdates = false
  var canCheckForUpdates = true
  private(set) var checkCount = 0

  func checkForUpdates() {
    checkCount += 1
  }
}

@MainActor
private struct TestDiagnosticLogger: DiagnosticLogging {}

private final class TestSentenceCardConfigurationStore:
  SentenceCardConfigurationStoring
{
  private(set) var savedValue: Bool

  init(isEnabled: Bool = false) {
    savedValue = isEnabled
  }

  func load() -> Bool {
    savedValue
  }

  func save(_ isEnabled: Bool) {
    savedValue = isEnabled
  }
}

@MainActor
private final class SentenceCardTranslationProvider: TranslationProviding {
  private let translations: [String: String]
  private(set) var translatedSources: [String] = []

  init(translations: [String: String]) {
    self.translations = translations
  }

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    throw TranslationError.invalidResponse
  }

  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult {
    translatedSources.append(sourceText)
    guard let translation = translations[sourceText] else {
      throw TranslationError.invalidResponse
    }
    return LongTextTranslationResult(
      sourceText: sourceText,
      translatedText: translation
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
private final class TestLongTextTranslationProvider: TranslationProviding {
  private(set) var lastLongTextSource: String?
  private(set) var lastRequest: TranslationRequest?

  func translate(_ request: TranslationRequest) async throws -> TranslationResult {
    lastRequest = request
    return TranslationResult(
      sourceText: request.sourceText,
      canonicalForm: request.sourceText,
      pronunciation: "",
      partOfSpeech: "noun",
      contextualMeaning: "惯例",
      exampleSentence: request.targetSentence ?? "",
      sentenceTranslation: "例句翻译"
    )
  }

  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult {
    lastLongTextSource = sourceText
    return LongTextTranslationResult(
      sourceText: sourceText,
      translatedText: "长文本译文"
    )
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
  private(set) var deletedItemIDs: [UUID] = []
  private(set) var canonicalUpdateInvocations: [CanonicalUpdateInvocation] = []
  private(set) var reviewInvocations: [ReviewInvocation] = []
  private(set) var nextReviewDateInvocations: [NextReviewDateInvocation] = []
  private(set) var reviewPausedInvocations: [ReviewPausedInvocation] = []
  private(set) var reviewResetInvocations: [ReviewResetInvocation] = []
  private var storedItems: [LearningItem]
  private var storedArchivedItems: [LearningItem]
  private var storedDueItems: [LearningItem]
  private var storedSummary: LearningSummary
  private var storedPendingDeletion: PendingLearningDeletion?
  private var pendingDeletionWasDue = false
  private let storedMergeSummary: LearningMergeSummary?
  private var canonicalUpdateResults: [LearningCanonicalUpdateResult]
  private let detailsUpdateError: TestLearningStoreError?

  init(
    summary: LearningSummary = LearningSummary(
      dueCount: 3,
      wordCount: 12,
      sentenceCount: 4
    ),
    items: [LearningItem] = [],
    archivedItems: [LearningItem] = [],
    dueItems: [LearningItem] = [],
    pendingDeletion: PendingLearningDeletion? = nil,
    mergeSummary: LearningMergeSummary? = nil,
    canonicalUpdateResults: [LearningCanonicalUpdateResult] = [],
    detailsUpdateError: TestLearningStoreError? = nil
  ) {
    storedSummary = summary
    storedItems = items
    storedArchivedItems = archivedItems
    storedDueItems = dueItems
    storedPendingDeletion = pendingDeletion
    storedMergeSummary = mergeSummary
    self.canonicalUpdateResults = canonicalUpdateResults
    self.detailsUpdateError = detailsUpdateError
  }

  func summary(at date: Date) async throws -> LearningSummary {
    storedSummary
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
    storedSummary = LearningSummary(
      dueCount: max(0, storedSummary.dueCount - 1),
      reviewedTodayCount: storedSummary.reviewedTodayCount + 1,
      streakDayCount: storedSummary.streakDayCount,
      wordCount: storedSummary.wordCount,
      sentenceCount: storedSummary.sentenceCount
    )
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

  func updateDetails(
    itemID: UUID,
    details: LearningItemDetailsUpdate
  ) async throws {
    if let detailsUpdateError {
      throw detailsUpdateError
    }
  }

  func updateItem(
    itemID: UUID,
    canonicalForm: String,
    details: LearningItemDetailsUpdate
  ) async throws -> LearningCanonicalUpdateResult {
    try await updateDetails(itemID: itemID, details: details)
    return canonicalUpdateResults.isEmpty ? .updated : canonicalUpdateResults.removeFirst()
  }

  func items() async throws -> [LearningItem] {
    storedItems
  }

  func archivedItems() async throws -> [LearningItem] {
    storedArchivedItems
  }

  func setArchived(itemIDs: [UUID], archivedAt: Date?) async throws {
    let selectedIDs = Set(itemIDs)
    if archivedAt == nil {
      let restored = storedArchivedItems.filter { selectedIDs.contains($0.id) }
      storedArchivedItems.removeAll { selectedIDs.contains($0.id) }
      storedItems.append(contentsOf: restored)
    } else {
      let archived = storedItems.filter { selectedIDs.contains($0.id) }
      storedItems.removeAll { selectedIDs.contains($0.id) }
      storedArchivedItems.append(contentsOf: archived)
    }
  }

  func scheduleDeletion(itemID: UUID, deleteAt: Date) async throws {
    guard
      let item = (storedItems + storedArchivedItems).first(where: { $0.id == itemID })
    else {
      throw TestLearningStoreError.updateFailed
    }
    storedPendingDeletion = PendingLearningDeletion(item: item, deleteAt: deleteAt)
    pendingDeletionWasDue = storedDueItems.contains(where: { $0.id == itemID })
    storedItems.removeAll { $0.id == itemID }
    storedArchivedItems.removeAll { $0.id == itemID }
    storedDueItems.removeAll { $0.id == itemID }
  }

  func cancelDeletion(itemID: UUID) async throws {
    guard let deletion = storedPendingDeletion, deletion.item.id == itemID else {
      throw TestLearningStoreError.updateFailed
    }
    if deletion.item.archivedAt == nil {
      storedItems.append(deletion.item)
    } else {
      storedArchivedItems.append(deletion.item)
    }
    if pendingDeletionWasDue {
      storedDueItems.append(deletion.item)
    }
    storedPendingDeletion = nil
    pendingDeletionWasDue = false
  }

  func pendingDeletion() async throws -> PendingLearningDeletion? {
    storedPendingDeletion
  }

  func deleteExpiredItems(at date: Date) async throws {
    guard let deletion = storedPendingDeletion, deletion.deleteAt <= date else {
      return
    }
    try await delete(itemID: deletion.item.id)
  }

  func delete(itemID: UUID) async throws {
    deletedItemIDs.append(itemID)
    storedItems.removeAll { $0.id == itemID }
    storedArchivedItems.removeAll { $0.id == itemID }
    storedDueItems.removeAll { $0.id == itemID }
    if storedPendingDeletion?.item.id == itemID {
      storedPendingDeletion = nil
      pendingDeletionWasDue = false
    }
  }

  func setNextReviewDate(itemID: UUID, nextReviewAt: Date) async throws {
    nextReviewDateInvocations.append(
      NextReviewDateInvocation(itemID: itemID, nextReviewAt: nextReviewAt)
    )
  }

  func setReviewPaused(itemID: UUID, isPaused: Bool) async throws {
    reviewPausedInvocations.append(
      ReviewPausedInvocation(itemID: itemID, isPaused: isPaused)
    )
  }

  func resetReviewProgress(itemID: UUID, resetAt: Date) async throws {
    reviewResetInvocations.append(
      ReviewResetInvocation(itemID: itemID, resetAt: resetAt)
    )
  }

  func exportArchive(exportedAt: Date) async throws -> LearningDataArchive {
    LearningDataArchive(exportedAt: exportedAt, items: [])
  }

  func importArchive(_ archive: LearningDataArchive) async throws -> LearningDataImportSummary {
    LearningDataImportSummary(importedItemCount: 0, mergedItemCount: 0)
  }

  func deleteAllLearningData() async throws {
    storedItems.removeAll()
    storedArchivedItems.removeAll()
    storedDueItems.removeAll()
    storedPendingDeletion = nil
  }
}

private enum TestLearningStoreError: Error {
  case updateFailed
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

private struct NextReviewDateInvocation: Equatable {
  let itemID: UUID
  let nextReviewAt: Date
}

private struct ReviewPausedInvocation: Equatable {
  let itemID: UUID
  let isPaused: Bool
}

private struct ReviewResetInvocation: Equatable {
  let itemID: UUID
  let resetAt: Date
}

@MainActor
private final class TestApplicationAPIKeyStore: APIKeyStoring {
  private(set) var savedAPIKeys: [TranslationProviderKind: String] = [:]

  init(apiKey: String? = nil) {
    if let apiKey {
      savedAPIKeys[.deepSeek] = apiKey
    }
  }

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
  private(set) var receivedReminders: [ReviewReminder?] = []
  private let error: TestReviewNotifierError?
  private let storedAuthorizationStatus: PreparationAuthorizationStatus
  private let authorizationRequestResult: Bool
  private(set) var didRequestAuthorization = false

  init(
    error: TestReviewNotifierError? = nil,
    authorizationStatus: PreparationAuthorizationStatus = .notDetermined,
    authorizationRequestResult: Bool = true
  ) {
    self.error = error
    storedAuthorizationStatus = authorizationStatus
    self.authorizationRequestResult = authorizationRequestResult
  }

  func authorizationStatus() async -> PreparationAuthorizationStatus {
    storedAuthorizationStatus
  }

  func requestAuthorization() async throws -> Bool {
    didRequestAuthorization = true
    return authorizationRequestResult
  }

  func replaceScheduledReminder(with reminder: ReviewReminder?) async throws {
    receivedReminders.append(reminder)
    if let error {
      throw error
    }
    lastReminder = reminder
  }
}

private enum TestReviewNotifierError: Error {
  case denied
}

private final class TestLoginItemController: LoginItemControlling {
  private(set) var isEnabled = false

  func setEnabled(_ isEnabled: Bool) throws {
    self.isEnabled = isEnabled
  }
}

@MainActor
private final class TestAccessibilityAuthorizer: AccessibilityAuthorizing {
  private(set) var status: PreparationAuthorizationStatus
  private(set) var didRequestAuthorization = false

  init(status: PreparationAuthorizationStatus = .authorized) {
    self.status = status
  }

  var authorizationStatus: PreparationAuthorizationStatus {
    status
  }

  func requestAuthorization() {
    didRequestAuthorization = true
  }
}

private final class TestPreparationStateStore: PreparationStateStoring {
  private(set) var hasCompletedInitialFlow: Bool

  init(hasCompletedInitialFlow: Bool = false) {
    self.hasCompletedInitialFlow = hasCompletedInitialFlow
  }

  func loadHasCompletedInitialFlow() -> Bool {
    hasCompletedInitialFlow
  }

  func saveHasCompletedInitialFlow(_ hasCompleted: Bool) {
    hasCompletedInitialFlow = hasCompleted
  }
}

private final class TestReviewReminderConfigurationStore:
  ReviewReminderConfigurationStoring
{
  private(set) var savedConfiguration: ReviewReminderConfiguration

  init(configuration: ReviewReminderConfiguration = .default) {
    savedConfiguration = configuration
  }

  func load() -> ReviewReminderConfiguration {
    savedConfiguration
  }

  func save(_ configuration: ReviewReminderConfiguration) {
    savedConfiguration = configuration
  }
}

private final class TestSpeechPlayer: SpeechPlaying {
  struct SpokenItem: Equatable {
    let text: String
    let voiceIdentifier: String?
    let rate: Float
  }

  private(set) var spokenItems: [SpokenItem] = []

  func speak(_ text: String) {
    spokenItems.append(
      SpokenItem(
        text: text,
        voiceIdentifier: nil,
        rate: LanguageAndSpeechPreferences.default.speechRate
      )
    )
  }

  func speak(
    _ text: String,
    voiceIdentifier: String?,
    rate: Float
  ) {
    spokenItems.append(
      SpokenItem(
        text: text,
        voiceIdentifier: voiceIdentifier,
        rate: rate
      )
    )
  }
}

private final class TestLanguageAndSpeechPreferencesStore:
  LanguageAndSpeechPreferencesStoring
{
  private(set) var preferences: LanguageAndSpeechPreferences

  init(preferences: LanguageAndSpeechPreferences = .default) {
    self.preferences = preferences
  }

  func load() -> LanguageAndSpeechPreferences {
    preferences
  }

  func save(_ preferences: LanguageAndSpeechPreferences) {
    self.preferences = preferences
  }
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

private final class TestTranslationShortcutStore: TranslationShortcutStoring {
  private(set) var savedShortcut: TranslationShortcutKey

  init(shortcut: TranslationShortcutKey = .default) {
    savedShortcut = shortcut
  }

  func load() -> TranslationShortcutKey {
    savedShortcut
  }

  func save(_ shortcut: TranslationShortcutKey) {
    savedShortcut = shortcut
  }
}

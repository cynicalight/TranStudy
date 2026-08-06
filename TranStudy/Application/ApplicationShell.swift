import Foundation
import NaturalLanguage
import Observation

enum TranslationConnectionStatus: Equatable {
  case idle
  case testing
  case connected
  case failed
}

enum TranslationStatus: Equatable {
  case idle
  case loading
  case ready
  case failed
}

enum TranslationShortcutRegistrationStatus: Equatable {
  case unknown
  case registered
  case failed(TranslationShortcutKey)
}

enum SentenceCardAdditionStatus: Equatable {
  case added
  case failed
}

enum LearningLibraryScope: Hashable {
  case active
  case archived
}

enum PreparationCapability: CaseIterable, Equatable, Identifiable {
  case accessibility
  case translationService
  case notifications

  var id: Self {
    self
  }
}

@MainActor
@Observable
final class ApplicationShell {
  let environment: ApplicationEnvironment
  let destinations = AppDestination.allCases
  var selectedDestination: AppDestination = .todayReview
  private(set) var learningSummary = LearningSummary.empty
  private(set) var lastReviewRefreshDate: Date?
  var translationDraft: TranslationDraft?
  private(set) var connectionStatus: TranslationConnectionStatus = .idle
  private(set) var isPreparationPresented: Bool
  private(set) var accessibilityAuthorizationStatus: PreparationAuthorizationStatus
  private(set) var notificationAuthorizationStatus: PreparationAuthorizationStatus =
    .notDetermined
  private(set) var isTranslationServiceConfigured: Bool
  private(set) var translationStatus: TranslationStatus = .idle
  private(set) var translationError: TranslationError?
  private(set) var translationSourceText = ""
  private(set) var translationPresentationTitle = "翻译剪贴板"
  private(set) var longTextTranslation: LongTextTranslationResult?
  private(set) var learningItems: [LearningItem] = []
  private(set) var archivedLearningItems: [LearningItem] = []
  private(set) var libraryScope: LearningLibraryScope = .active
  private(set) var isLibrarySelecting = false
  private(set) var selectedLearningItemIDs: Set<UUID> = []
  @ObservationIgnored private var librarySearchIndex: [UUID: [String]] = [:]
  var librarySearchQuery = "" {
    didSet {
      selectedLearningItemIDs.formIntersection(displayedLearningItems.map(\.id))
    }
  }
  private(set) var reviewQueue: [LearningItem] = []
  private(set) var remainingReviewBatches: [[LearningItem]] = []
  private(set) var isReviewAnswerVisible = false
  private(set) var isReviewRating = false
  private(set) var selectedReviewRating: ReviewRating?
  private(set) var spellingQueue: [LearningItem] = []
  private(set) var spellingReviewResult: Bool?
  private(set) var isSpellingReviewSubmitting = false
  private(set) var reviewReminderConfiguration: ReviewReminderConfiguration
  private(set) var isLaunchAtLoginEnabled: Bool
  private(set) var automaticallyChecksForUpdates: Bool
  private(set) var pendingLearningMerge: LearningMergeSummary?
  private(set) var learningAdditionErrorMessage: String?
  private(set) var pendingLibraryMerge: LearningMergeSummary?
  private(set) var pendingLibraryDeletion: LearningItem?
  private(set) var translationPanelPosition: TranslationPanelPosition
  private(set) var translationProviderConfiguration: TranslationProviderConfiguration
  private(set) var selectionConfiguration: SelectionConfiguration
  private(set) var translationShortcut: TranslationShortcutKey
  private(set) var isSentenceCardsEnabled: Bool
  private(set) var languageAndSpeechPreferences: LanguageAndSpeechPreferences
  private(set) var isAddingSentenceCard = false
  private(set) var sentenceCardAdditionStatus: SentenceCardAdditionStatus?
  private(set) var translationShortcutRegistrationStatus: TranslationShortcutRegistrationStatus =
    .unknown
  @ObservationIgnored var onTranslationShortcutChange: ((TranslationShortcutKey) -> Bool)?
  @ObservationIgnored var onReviewReminderConfigurationChange: (() -> Void)?
  @ObservationIgnored private var pendingLibraryDeletionTask: Task<Void, Never>?
  private var activeTranslationID: UUID?
  private var translationSuggestedCanonicalForm = ""
  private var translationSourceApplicationName = "剪贴板"
  private var translationSourceApplicationIdentifier: String?
  private var pendingLearningAddition: LearningAddition?
  private var pendingLibraryCanonicalUpdate: (itemID: UUID, canonicalForm: String)?

  var currentReviewItem: LearningItem? {
    reviewQueue.first
  }

  var remainingReviewCount: Int {
    remainingReviewBatches.reduce(0) { $0 + $1.count }
  }

  var hasMoreReviewBatches: Bool {
    !remainingReviewBatches.isEmpty
  }

  var currentSpellingItem: LearningItem? {
    spellingQueue.first
  }

  var isLongTextTranslationPresentation: Bool {
    translationPresentationTitle == "翻译长文本"
  }

  var interfaceLanguage: InterfaceLanguage {
    languageAndSpeechPreferences.interfaceLanguage
  }

  var chineseWritingSystem: ChineseWritingSystem {
    languageAndSpeechPreferences.chineseWritingSystem
  }

  var availableSpeechVoices: [SpeechVoice] {
    environment.speech.availableVoices
  }

  var canCheckForUpdates: Bool {
    environment.updates.canCheckForUpdates
  }

  var missingPreparationCapabilities: [PreparationCapability] {
    var capabilities: [PreparationCapability] = []
    if accessibilityAuthorizationStatus != .authorized {
      capabilities.append(.accessibility)
    }
    if !isTranslationServiceConfigured {
      capabilities.append(.translationService)
    }
    if notificationAuthorizationStatus != .authorized {
      capabilities.append(.notifications)
    }
    return capabilities
  }

  init(environment: ApplicationEnvironment) {
    self.environment = environment
    isPreparationPresented =
      !environment.preparationStateStore.loadHasCompletedInitialFlow()
    accessibilityAuthorizationStatus =
      environment.accessibilityAuthorization.authorizationStatus
    isTranslationServiceConfigured = Self.hasConfiguredTranslationService(
      in: environment,
      provider: environment.providerConfigurationStore.load().provider
    )
    translationPanelPosition = environment.panelPositionStore.load()
    translationProviderConfiguration = environment.providerConfigurationStore.load()
    selectionConfiguration = environment.selectionConfigurationStore.load()
    translationShortcut = environment.shortcutStore.load()
    isSentenceCardsEnabled = environment.sentenceCardConfigurationStore.load()
    languageAndSpeechPreferences = environment.languageAndSpeechPreferencesStore.load()
    reviewReminderConfiguration = environment.reviewReminderConfigurationStore.load()
    isLaunchAtLoginEnabled = environment.loginItem.isEnabled
    automaticallyChecksForUpdates = environment.updates.automaticallyChecksForUpdates
  }

  func refreshPreparationStatus() async {
    accessibilityAuthorizationStatus =
      environment.accessibilityAuthorization.authorizationStatus
    notificationAuthorizationStatus = await environment.notifications.authorizationStatus()
    isTranslationServiceConfigured = Self.hasConfiguredTranslationService(
      in: environment,
      provider: translationProviderConfiguration.provider
    )
  }

  func requestAccessibilityAuthorization() {
    environment.accessibilityAuthorization.requestAuthorization()
    accessibilityAuthorizationStatus =
      environment.accessibilityAuthorization.authorizationStatus
  }

  func requestNotificationAuthorization() async {
    do {
      let granted = try await environment.notifications.requestAuthorization()
      notificationAuthorizationStatus = granted ? .authorized : .denied
    } catch {
      notificationAuthorizationStatus = .denied
    }
  }

  func presentPreparation() {
    isPreparationPresented = true
  }

  func completeInitialPreparation() {
    environment.preparationStateStore.saveHasCompletedInitialFlow(true)
    isPreparationPresented = false
  }

  private static func hasConfiguredTranslationService(
    in environment: ApplicationEnvironment,
    provider: TranslationProviderKind
  ) -> Bool {
    do {
      let apiKey = try environment.apiKeyStore.loadAPIKey(for: provider)
      return !(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    } catch {
      return false
    }
  }

  func refreshTodayReview() async {
    do {
      let now = environment.clock.now
      let summary = try await environment.learningStore.summary(at: now)
      let dueItems = try await environment.learningStore.dueItems(at: now)
      let queue = DailyReviewQueueBuilder().makeQueue(
        from: dueItems,
        seed: DailyReviewQueueBuilder.seed(for: now)
      )
      let batches = queue.batches
      learningSummary = summary
      reviewQueue = batches.first ?? []
      remainingReviewBatches = Array(batches.dropFirst())
      spellingQueue = queue.items.filter { $0.kind == .word }
      isReviewAnswerVisible = false
      selectedReviewRating = nil
      spellingReviewResult = nil
      lastReviewRefreshDate = now
    } catch {
      // A later ticket will expose recoverable loading errors in the review UI.
    }
  }

  func sendReviewReminderIfNeeded() async {
    do {
      let now = environment.clock.now
      let dueItems = try await environment.learningStore.dueItems(at: now)
      let reminder =
        reviewReminderConfiguration.isEnabled && !dueItems.isEmpty
        ? ReviewReminder(
          date: now.addingTimeInterval(1),
          dueCount: dueItems.count
        )
        : nil
      try await environment.notifications.replaceScheduledReminder(with: reminder)
    } catch {
      // Notification permission and scheduling failures never block learning.
    }
  }

  func revealCurrentReviewAnswer() {
    guard currentReviewItem != nil else {
      return
    }
    isReviewAnswerVisible = true
  }

  func rateCurrentReview(_ rating: ReviewRating) async {
    guard
      currentReviewItem != nil,
      selectedReviewRating == nil,
      !isReviewRating
    else {
      return
    }

    selectedReviewRating = rating
    isReviewAnswerVisible = true
  }

  func cancelCurrentReviewRating() {
    guard selectedReviewRating != nil, !isReviewRating else {
      return
    }
    selectedReviewRating = nil
  }

  func confirmCurrentReviewOrRemember() async {
    if selectedReviewRating == nil {
      await rateCurrentReview(.remembered)
    }
    await advanceToNextReview()
  }

  func advanceToNextReview() async {
    guard
      let currentReviewItem,
      let selectedReviewRating,
      !reviewQueue.isEmpty,
      !isReviewRating
    else {
      return
    }

    isReviewRating = true
    defer {
      isReviewRating = false
    }
    let now = environment.clock.now
    do {
      let result = try await environment.learningStore.recordReview(
        itemID: currentReviewItem.id,
        rating: selectedReviewRating,
        reviewedAt: now
      )
      if Calendar.autoupdatingCurrent.startOfDay(for: result.nextReviewAt)
        <= Calendar.autoupdatingCurrent.startOfDay(for: now)
      {
        reviewQueue.append(currentReviewItem)
      }
      learningSummary = try await environment.learningStore.summary(at: now)
      lastReviewRefreshDate = now
      if learningSummary.dueCount == 0 {
        try? await environment.notifications.replaceScheduledReminder(with: nil)
      }
      reviewQueue.removeFirst()
      isReviewAnswerVisible = false
      self.selectedReviewRating = nil
    } catch {
      // Keep the selected rating available for another submission attempt.
    }
  }

  func submitCurrentSpelling(_ attempt: String) async {
    guard
      let currentSpellingItem,
      spellingReviewResult == nil,
      !isSpellingReviewSubmitting
    else {
      return
    }

    let isCorrect = SpellingAnswer.matches(
      attempt,
      expected: currentSpellingItem.canonicalForm
    )
    guard !isCorrect else {
      spellingReviewResult = true
      return
    }

    isSpellingReviewSubmitting = true
    defer {
      isSpellingReviewSubmitting = false
    }
    let now = environment.clock.now
    do {
      _ = try await environment.learningStore.recordReview(
        itemID: currentSpellingItem.id,
        rating: .forgot,
        reviewedAt: now
      )
      spellingReviewResult = false
      learningSummary = try await environment.learningStore.summary(at: now)
      lastReviewRefreshDate = now
    } catch {
      // Keep the current spelling card available when persistence fails.
    }
  }

  func advanceToNextSpellingReview() {
    guard let wasCorrect = spellingReviewResult, !spellingQueue.isEmpty else {
      return
    }
    let item = spellingQueue.removeFirst()
    if !wasCorrect {
      spellingQueue.append(item)
    }
    spellingReviewResult = nil
  }

  func startNextReviewBatch() {
    guard reviewQueue.isEmpty, !remainingReviewBatches.isEmpty else {
      return
    }
    reviewQueue = remainingReviewBatches.removeFirst()
    isReviewAnswerVisible = false
    selectedReviewRating = nil
  }

  func startTodayReview() async {
    selectedDestination = .todayReview
    await refreshTodayReview()
  }

  func setReviewReminderEnabled(_ isEnabled: Bool) async {
    reviewReminderConfiguration.isEnabled = isEnabled
    environment.reviewReminderConfigurationStore.save(reviewReminderConfiguration)
    onReviewReminderConfigurationChange?()
    if !isEnabled {
      try? await environment.notifications.replaceScheduledReminder(with: nil)
    }
  }

  func setReviewReminderTime(hour: Int, minute: Int) async {
    reviewReminderConfiguration.hour = min(max(hour, 0), 23)
    reviewReminderConfiguration.minute = min(max(minute, 0), 59)
    environment.reviewReminderConfigurationStore.save(reviewReminderConfiguration)
    onReviewReminderConfigurationChange?()
  }

  func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
    do {
      try environment.loginItem.setEnabled(isEnabled)
    } catch {
      // Keep the system-reported state when registration is rejected.
    }
    isLaunchAtLoginEnabled = environment.loginItem.isEnabled
  }

  func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
    environment.updates.automaticallyChecksForUpdates = isEnabled
    automaticallyChecksForUpdates = environment.updates.automaticallyChecksForUpdates
  }

  func checkForUpdates() {
    guard environment.updates.canCheckForUpdates else {
      return
    }
    environment.updates.checkForUpdates()
  }

  func setInterfaceLanguage(_ language: InterfaceLanguage) {
    languageAndSpeechPreferences.interfaceLanguage = language
    saveLanguageAndSpeechPreferences()
  }

  func setChineseWritingSystem(_ writingSystem: ChineseWritingSystem) {
    languageAndSpeechPreferences.chineseWritingSystem = writingSystem
    saveLanguageAndSpeechPreferences()
  }

  func setSpeechVoiceIdentifier(_ identifier: String?) {
    languageAndSpeechPreferences.speechVoiceIdentifier = identifier
    saveLanguageAndSpeechPreferences()
  }

  func setSpeechRate(_ rate: Float) {
    languageAndSpeechPreferences.speechRate = min(max(rate, 0.35), 0.65)
    saveLanguageAndSpeechPreferences()
  }

  func setAutomaticallySpeaksTranslations(_ isEnabled: Bool) {
    languageAndSpeechPreferences.automaticallySpeaksTranslations = isEnabled
    saveLanguageAndSpeechPreferences()
  }

  func speak(_ text: String) {
    environment.speech.speak(
      text,
      voiceIdentifier: languageAndSpeechPreferences.speechVoiceIdentifier,
      rate: languageAndSpeechPreferences.speechRate
    )
  }

  private func saveLanguageAndSpeechPreferences() {
    environment.languageAndSpeechPreferencesStore.save(languageAndSpeechPreferences)
  }

  func translateClipboard() async {
    await translateClipboard(environment.clipboard.readText())
  }

  func translateClipboard(_ sourceText: String?) async {
    guard let sourceText else {
      translationStatus = .failed
      return
    }

    await translateInput(sourceText, selection: nil)
  }

  func translateSelection(_ snapshot: SelectionSnapshot) async {
    guard snapshot.hasContext else {
      selectionDebugLog("selection translation rejected: sentence context unavailable")
      translationStatus = .failed
      return
    }
    await translateInput(snapshot.selectedText, selection: snapshot)
  }

  private func translateInput(
    _ inputText: String,
    selection: SelectionSnapshot?
  ) async {
    sentenceCardAdditionStatus = nil
    let sourceText = TranslationTextNormalizer.collapseWhitespace(in: inputText)
    guard !sourceText.isEmpty else {
      selectionDebugLog(
        "translation input rejected: source=\(selection == nil ? "clipboard" : "selection") reason=empty"
      )
      translationStatus = .failed
      return
    }
    if sourceText.count != inputText.count {
      selectionDebugLog(
        "translation input whitespace normalized: originalLength=\(inputText.count) normalizedLength=\(sourceText.count)"
      )
    }

    let isWordOrShortPhrase = Self.isWordOrShortPhrase(sourceText)
    if let selection {
      translationSourceApplicationName = selection.sourceApplicationName
      translationSourceApplicationIdentifier = selection.sourceApplicationIdentifier
    } else {
      translationSourceApplicationIdentifier = nil
    }
    selectionDebugLog(
      "translation input classified: source=\(selection == nil ? "clipboard" : "selection") selectedLength=\(sourceText.count) mode=\(isWordOrShortPhrase ? "word-or-phrase" : "long-text")"
    )

    if isWordOrShortPhrase {
      if let selection {
        await translate(
          TranslationRequest(
            sourceText: sourceText,
            context: selection.translationContext,
            kind: .contextualSelection,
            targetSentence: selection.targetSentence,
            selectionWordContext: selection.wordContext
          ))
      } else {
        await translate(TranslationRequest(sourceText: sourceText))
      }
    } else {
      await translateLongText(sourceText)
    }
  }

  private func translate(_ request: TranslationRequest) async {
    let request = TranslationRequest(
      sourceText: request.sourceText,
      context: request.context,
      kind: request.kind,
      targetSentence: request.targetSentence,
      selectionWordContext: request.selectionWordContext,
      chineseWritingSystem: chineseWritingSystem
    )
    let translationID = UUID()
    activeTranslationID = translationID
    translationSourceText = request.sourceText
    translationError = nil
    longTextTranslation = nil
    translationStatus = .loading
    let startedAt = beginTranslationDiagnostics()

    do {
      let result = try await environment.translation.translate(request)
      try Task.checkCancellation()
      guard activeTranslationID == translationID else {
        return
      }

      activeTranslationID = nil
      translationDraft = TranslationDraft(result: result)
      translationSuggestedCanonicalForm = result.canonicalForm
      pendingLearningMerge = nil
      pendingLearningAddition = nil
      translationStatus = .ready
      finishTranslationDiagnostics(stage: .translationSucceeded, startedAt: startedAt)
      if languageAndSpeechPreferences.automaticallySpeaksTranslations {
        speak(result.sourceText)
      }
      selectionDebugLog("translation succeeded: kind=\(request.kind)")
    } catch is CancellationError {
      if activeTranslationID == translationID {
        activeTranslationID = nil
        translationStatus = .idle
      }
      selectionDebugLog("translation cancelled")
    } catch {
      if activeTranslationID == translationID {
        activeTranslationID = nil
        translationError = error as? TranslationError
        translationStatus = .failed
      }
      finishTranslationDiagnostics(
        stage: .translationFailed,
        error: error,
        startedAt: startedAt
      )
      selectionDebugLog("translation failed: errorType=\(String(reflecting: type(of: error)))")
    }
  }

  func makeLearningDataExport() async throws -> Data {
    let archive = try await environment.learningStore.exportArchive(
      exportedAt: environment.clock.now
    )
    let data = try await Task.detached(priority: .userInitiated) {
      try JSONEncoder.tranStudy.encode(archive)
    }.value
    environment.diagnostics.record(stage: .learningDataExported)
    return data
  }

  func importLearningData(_ data: Data) async throws -> LearningDataImportSummary {
    let archive = try JSONDecoder.tranStudy.decode(LearningDataArchive.self, from: data)
    let summary = try await environment.learningStore.importArchive(archive)
    environment.diagnostics.record(stage: .learningDataImported)
    await refreshTodayReview()
    await refreshLibrary()
    return summary
  }

  func clearTranslationCache() throws {
    try environment.translationCache.clear()
    environment.diagnostics.record(stage: .translationCacheCleared)
  }

  func clearAllLearningData() async throws {
    try await environment.learningStore.deleteAllLearningData()
    environment.diagnostics.record(stage: .learningDataCleared)
    await refreshTodayReview()
    await refreshLibrary()
  }

  func makeDiagnosticExport() throws -> Data {
    let archive = environment.diagnostics.exportArchive(exportedAt: environment.clock.now)
    return try JSONEncoder.tranStudy.encode(archive)
  }

  private func diagnosticErrorType(for error: Error) -> DiagnosticErrorType {
    guard let error = error as? TranslationError else {
      return .unknown
    }
    switch error {
    case .notConfigured, .inputTooLong:
      return .configuration
    case .invalidRequest:
      return .requestRejected
    case .authenticationFailed:
      return .authentication
    case .quotaExceeded:
      return .quota
    case .rateLimited:
      return .rateLimited
    case .timedOut:
      return .timeout
    case .networkUnavailable, .serviceUnavailable:
      return .network
    case .invalidResponse(let failure):
      switch failure {
      case .malformedPayload:
        return .malformedResponse
      case .unexpectedInputKind:
        return .unexpectedResponseKind
      case .missingRequiredContent:
        return .missingResponseContent
      case .invalidEnglishContent:
        return .invalidEnglishResponse
      case .invalidChineseContent:
        return .invalidChineseResponse
      }
    }
  }

  private func beginTranslationDiagnostics() -> Date {
    let startedAt = Date()
    environment.diagnostics.record(
      stage: .translationStarted,
      sourceApplicationIdentifier: translationSourceApplicationIdentifier
    )
    return startedAt
  }

  private func finishTranslationDiagnostics(
    stage: DiagnosticStage,
    error: Error? = nil,
    startedAt: Date
  ) {
    environment.diagnostics.record(
      stage: stage,
      sourceApplicationIdentifier: translationSourceApplicationIdentifier,
      errorType: error.map(diagnosticErrorType(for:)),
      durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
    )
  }

  private func translateLongText(_ sourceText: String) async {
    let translationID = UUID()
    activeTranslationID = translationID
    translationSourceText = sourceText
    translationPresentationTitle = "翻译长文本"
    translationDraft = nil
    longTextTranslation = nil
    translationError = nil
    translationStatus = .loading
    let startedAt = beginTranslationDiagnostics()

    do {
      let result = try await environment.translation.translateLongText(
        sourceText,
        chineseWritingSystem: chineseWritingSystem
      )
      try Task.checkCancellation()
      guard activeTranslationID == translationID else {
        return
      }

      activeTranslationID = nil
      longTextTranslation = result
      translationStatus = .ready
      finishTranslationDiagnostics(stage: .translationSucceeded, startedAt: startedAt)
      selectionDebugLog(
        "long text translation succeeded: sourceLength=\(sourceText.count) translatedLength=\(result.translatedText.count)"
      )
    } catch is CancellationError {
      if activeTranslationID == translationID {
        activeTranslationID = nil
        translationStatus = .idle
      }
      selectionDebugLog("long text translation cancelled")
    } catch {
      if activeTranslationID == translationID {
        activeTranslationID = nil
        translationError = error as? TranslationError
        translationStatus = .failed
      }
      finishTranslationDiagnostics(
        stage: .translationFailed,
        error: error,
        startedAt: startedAt
      )
      selectionDebugLog(
        "long text translation failed: errorType=\(String(reflecting: type(of: error)))"
      )
    }
  }

  func translateLongTextSelection(_ selectedRange: NSRange) async {
    guard let request = longTextSelectionRequest(for: selectedRange) else {
      selectionDebugLog("long text selection ignored: selection is not a word or short phrase")
      return
    }

    translationPresentationTitle = "学习长文本选词"
    await translate(request)
  }

  func canTranslateLongTextSelection(_ selectedRange: NSRange) -> Bool {
    longTextSelectionRequest(for: selectedRange) != nil
  }

  var canAddLongTextSentence: Bool {
    isSentenceCardsEnabled && !isAddingSentenceCard
      && sentenceCardDraftForCurrentLongText != nil
  }

  func addLongTextSentence() async {
    guard canAddLongTextSentence, let draft = sentenceCardDraftForCurrentLongText else {
      return
    }

    isAddingSentenceCard = true
    sentenceCardAdditionStatus = nil
    defer {
      isAddingSentenceCard = false
    }

    do {
      try await environment.learningStore.add(
        LearningAddition(
          kind: .sentence,
          draft: draft,
          sourceApplicationName: translationSourceApplicationName,
          createdAt: environment.clock.now
        ))
      await refreshTodayReview()
      await refreshLibrary()
      sentenceCardAdditionStatus = .added
    } catch {
      sentenceCardAdditionStatus = .failed
      selectionDebugLog(
        "sentence card addition failed: errorType=\(String(reflecting: type(of: error)))"
      )
    }
  }

  private var sentenceCardDraftForCurrentLongText: TranslationDraft? {
    guard let result = longTextTranslation else {
      return nil
    }
    let source = result.sourceText as NSString
    guard
      source.length > 0,
      let context = SelectionSentenceContext.extract(
        from: result.sourceText,
        selectedRange: CFRange(location: 0, length: source.length)
      )
    else {
      return nil
    }
    let sentence = TranslationTextNormalizer.collapseWhitespace(in: context.targetSentence)
    guard sentence == TranslationTextNormalizer.collapseWhitespace(in: result.sourceText) else {
      return nil
    }
    return TranslationDraft(
      sourceText: sentence,
      canonicalForm: sentence,
      pronunciation: "",
      partOfSpeech: "",
      contextualMeaning: "",
      exampleSentence: sentence,
      sentenceTranslation: result.translatedText
    )
  }

  private func longTextSelectionRequest(for selectedRange: NSRange) -> TranslationRequest? {
    guard let longTextTranslation else {
      return nil
    }
    let source = longTextTranslation.sourceText as NSString
    guard
      selectedRange.location >= 0,
      selectedRange.length > 0,
      selectedRange.location <= source.length,
      selectedRange.length <= source.length - selectedRange.location
    else {
      return nil
    }

    let selectedText = source.substring(with: selectedRange)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      Self.isValidLongTextSelection(selectedText),
      let context = SelectionSentenceContext.extract(
        from: longTextTranslation.sourceText,
        selectedRange: CFRange(
          location: selectedRange.location,
          length: selectedRange.length
        )
      )
    else {
      return nil
    }

    return TranslationRequest(
      sourceText: selectedText,
      context: "Target sentence:\n\(context.targetSentence)",
      kind: .contextualSelection,
      targetSentence: context.targetSentence
    )
  }

  private static func isValidLongTextSelection(_ sourceText: String) -> Bool {
    Self.isWithinShortPhraseLimits(sourceText)
  }

  private static func isWithinShortPhraseLimits(_ sourceText: String) -> Bool {
    guard
      !sourceText.isEmpty,
      sourceText.count <= 160,
      !sourceText.contains(where: \.isNewline)
    else {
      return false
    }

    return (1...8).contains(sourceText.split(whereSeparator: \.isWhitespace).count)
  }

  func addCurrentDraftToLearning() async {
    guard let translationDraft else {
      selectionDebugLog("add to learning ignored: no translation draft")
      return
    }

    learningAdditionErrorMessage = nil

    selectionDebugLog(
      "add to learning started: sourceApp=\(translationSourceApplicationName) canonicalLength=\(translationDraft.canonicalForm.count)"
    )
    let addition = LearningAddition(
      draft: translationDraft,
      sourceApplicationName: translationSourceApplicationName,
      createdAt: environment.clock.now
    )

    do {
      let correctedCanonicalForm =
        NormalizedCanonicalForm(translationDraft.canonicalForm)
        != NormalizedCanonicalForm(translationSuggestedCanonicalForm)
      if correctedCanonicalForm {
        if let mergeSummary = try await environment.learningStore.mergeSummary(for: addition) {
          pendingLearningMerge = mergeSummary
          pendingLearningAddition = addition
          selectionDebugLog("add to learning paused: merge confirmation required")
          return
        }
      }

      try await persistLearningAddition(addition)
    } catch {
      selectionDebugLog("add to learning failed: errorType=\(String(reflecting: type(of: error)))")
      handleLearningAdditionFailure()
    }
  }

  func confirmPendingLearningMerge() async {
    guard let pendingLearningAddition else {
      return
    }

    learningAdditionErrorMessage = nil

    do {
      try await persistLearningAddition(pendingLearningAddition)
    } catch {
      handleLearningAdditionFailure()
    }
  }

  func cancelPendingLearningMerge() {
    pendingLearningMerge = nil
    pendingLearningAddition = nil
  }

  func clearLearningAdditionError() {
    learningAdditionErrorMessage = nil
  }

  func refreshLibrary() async {
    do {
      try await environment.learningStore.deleteExpiredItems(at: environment.clock.now)
      let persistedDeletion = try await environment.learningStore.pendingDeletion()
      if let persistedDeletion,
        pendingLibraryDeletion?.id != persistedDeletion.item.id
      {
        pendingLibraryDeletion = persistedDeletion.item
        scheduleLibraryDeletionFinalization(
          itemID: persistedDeletion.item.id,
          deleteAt: persistedDeletion.deleteAt
        )
      } else if persistedDeletion == nil {
        pendingLibraryDeletionTask?.cancel()
        pendingLibraryDeletionTask = nil
        pendingLibraryDeletion = nil
      }
      learningItems = try await environment.learningStore.items()
      archivedLearningItems = try await environment.learningStore.archivedItems()
      rebuildLibrarySearchIndex()
      selectedLearningItemIDs.formIntersection(displayedLearningItems.map(\.id))
    } catch {
      // A later ticket exposes recoverable library loading failures.
    }
  }

  var displayedLearningItems: [LearningItem] {
    let scopedItems =
      libraryScope == .active
      ? learningItems
      : archivedLearningItems
    let visibleItems = scopedItems.filter { $0.id != pendingLibraryDeletion?.id }
    let query = normalizedLibrarySearchText(librarySearchQuery)
    guard !query.isEmpty else {
      return visibleItems
    }
    return visibleItems.filter { item in
      librarySearchIndex[item.id, default: []].contains {
        $0.contains(query)
      }
    }
  }

  func setLibraryScope(_ scope: LearningLibraryScope) {
    libraryScope = scope
    cancelLibrarySelection()
  }

  func beginLibrarySelection() {
    isLibrarySelecting = true
    selectedLearningItemIDs = []
  }

  func cancelLibrarySelection() {
    isLibrarySelecting = false
    selectedLearningItemIDs = []
  }

  func toggleLibrarySelection(_ itemID: UUID) {
    guard isLibrarySelecting, displayedLearningItems.contains(where: { $0.id == itemID }) else {
      return
    }
    if selectedLearningItemIDs.contains(itemID) {
      selectedLearningItemIDs.remove(itemID)
    } else {
      selectedLearningItemIDs.insert(itemID)
    }
  }

  func selectAllLibraryItems() {
    guard isLibrarySelecting else {
      return
    }
    selectedLearningItemIDs = Set(displayedLearningItems.map(\.id))
  }

  func archiveSelectedLibraryItems() async {
    await setSelectedLibraryItemsArchived(at: environment.clock.now)
  }

  func restoreSelectedLibraryItems() async {
    await setSelectedLibraryItemsArchived(at: nil)
  }

  func addSelectedLibraryItemsToTodayReview() async {
    guard libraryScope == .active else {
      return
    }
    let selectedIDs = Array(selectedLearningItemIDs)
    guard !selectedIDs.isEmpty else {
      return
    }

    let now = environment.clock.now
    do {
      for itemID in selectedIDs {
        try await environment.learningStore.setReviewPaused(itemID: itemID, isPaused: false)
        try await environment.learningStore.setNextReviewDate(itemID: itemID, nextReviewAt: now)
      }
      cancelLibrarySelection()
      await refreshTodayReview()
      await refreshLibrary()
    } catch {
      // Keep the selection so the user can retry.
    }
  }

  func stageLibraryItemDeletion(itemID: UUID) async -> Bool {
    guard pendingLibraryDeletion == nil,
      let item = (learningItems + archivedLearningItems).first(where: { $0.id == itemID })
    else {
      return false
    }
    let deleteAt = environment.clock.now.addingTimeInterval(10)
    do {
      try await environment.learningStore.scheduleDeletion(
        itemID: itemID,
        deleteAt: deleteAt
      )
      pendingLibraryDeletion = item
      selectedLearningItemIDs.remove(itemID)
      scheduleLibraryDeletionFinalization(itemID: itemID, deleteAt: deleteAt)
      await refreshTodayReview()
      await refreshLibrary()
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  func undoLibraryItemDeletion() async -> Bool {
    guard let itemID = pendingLibraryDeletion?.id else {
      return false
    }
    do {
      try await environment.learningStore.cancelDeletion(itemID: itemID)
      pendingLibraryDeletionTask?.cancel()
      pendingLibraryDeletionTask = nil
      pendingLibraryDeletion = nil
      await refreshTodayReview()
      await refreshLibrary()
      return true
    } catch {
      return false
    }
  }

  @discardableResult
  func finalizeLibraryItemDeletion(itemID: UUID) async -> Bool {
    guard let pendingLibraryDeletion, pendingLibraryDeletion.id == itemID else {
      return false
    }
    do {
      try await environment.learningStore.delete(itemID: itemID)
      pendingLibraryDeletionTask = nil
      self.pendingLibraryDeletion = nil
      await refreshTodayReview()
      await refreshLibrary()
      return true
    } catch {
      pendingLibraryDeletionTask = nil
      self.pendingLibraryDeletion = nil
      return false
    }
  }

  private func scheduleLibraryDeletionFinalization(
    itemID: UUID,
    deleteAt: Date
  ) {
    pendingLibraryDeletionTask?.cancel()
    let remainingSeconds = max(0, deleteAt.timeIntervalSince(environment.clock.now))
    pendingLibraryDeletionTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(remainingSeconds))
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      await self?.finalizeLibraryItemDeletion(itemID: itemID)
    }
  }

  private func setSelectedLibraryItemsArchived(at archivedAt: Date?) async {
    let selectedIDs = Array(selectedLearningItemIDs)
    guard !selectedIDs.isEmpty else {
      return
    }
    do {
      try await environment.learningStore.setArchived(
        itemIDs: selectedIDs,
        archivedAt: archivedAt
      )
      cancelLibrarySelection()
      await refreshTodayReview()
      await refreshLibrary()
    } catch {
      // Keep the selection so the user can retry.
    }
  }

  private func rebuildLibrarySearchIndex() {
    librarySearchIndex = Dictionary(
      uniqueKeysWithValues: (learningItems + archivedLearningItems).map {
        ($0.id, librarySearchFields(for: $0).map(normalizedLibrarySearchText))
      }
    )
  }

  private func librarySearchFields(for item: LearningItem) -> [String] {
    let itemText = [
      item.canonicalForm,
      item.sourceText,
      item.contextualMeaning,
      item.exampleSentence,
      item.sentenceTranslation,
    ]
    let encounterText = item.encounters.flatMap {
      [$0.sourceText, $0.contextualMeaning, $0.exampleSentence, $0.sentenceTranslation]
    }
    let customExampleText = item.customExamples.flatMap {
      [$0.englishText, $0.chineseTranslation]
    }
    return itemText + encounterText + customExampleText
  }

  private func normalizedLibrarySearchText(_ text: String) -> String {
    TranslationTextNormalizer.collapseWhitespace(in: text)
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: .current
      )
  }

  func saveLearningItem(
    itemID: UUID,
    canonicalForm: String,
    details: LearningItemDetailsUpdate
  ) async -> Bool {
    do {
      let result = try await environment.learningStore.updateItem(
        itemID: itemID,
        canonicalForm: canonicalForm,
        details: details
      )
      switch result {
      case .updated, .merged:
        pendingLibraryMerge = nil
        pendingLibraryCanonicalUpdate = nil
        await refreshLibrary()
      case .requiresConfirmation(let summary):
        pendingLibraryMerge = summary
        pendingLibraryCanonicalUpdate = (itemID, canonicalForm)
      }
      return true
    } catch {
      return false
    }
  }

  func setLearningItemNextReviewDate(
    itemID: UUID,
    nextReviewAt: Date
  ) async -> Bool {
    do {
      try await environment.learningStore.setNextReviewDate(
        itemID: itemID,
        nextReviewAt: nextReviewAt
      )
      await refreshTodayReview()
      await refreshLibrary()
      return true
    } catch {
      return false
    }
  }

  func setLearningItemReviewPaused(
    itemID: UUID,
    isPaused: Bool
  ) async -> Bool {
    do {
      try await environment.learningStore.setReviewPaused(
        itemID: itemID,
        isPaused: isPaused
      )
      await refreshTodayReview()
      await refreshLibrary()
      return true
    } catch {
      return false
    }
  }

  func resetLearningItemReviewProgress(itemID: UUID) async -> Date? {
    let resetAt = environment.clock.now
    do {
      try await environment.learningStore.resetReviewProgress(
        itemID: itemID,
        resetAt: resetAt
      )
      await refreshTodayReview()
      await refreshLibrary()
      return resetAt
    } catch {
      return nil
    }
  }

  func updateLearningItemCanonicalForm(itemID: UUID, canonicalForm: String) async {
    do {
      let result = try await environment.learningStore.updateCanonicalForm(
        itemID: itemID,
        canonicalForm: canonicalForm,
        confirmMerge: false
      )
      switch result {
      case .updated, .merged:
        pendingLibraryMerge = nil
        pendingLibraryCanonicalUpdate = nil
        await refreshLibrary()
      case .requiresConfirmation(let summary):
        pendingLibraryMerge = summary
        pendingLibraryCanonicalUpdate = (itemID, canonicalForm)
      }
    } catch {
      // Keep the current library contents available when the correction fails.
    }
  }

  func confirmPendingLibraryMerge() async {
    guard let pendingLibraryCanonicalUpdate else {
      return
    }

    do {
      _ = try await environment.learningStore.updateCanonicalForm(
        itemID: pendingLibraryCanonicalUpdate.itemID,
        canonicalForm: pendingLibraryCanonicalUpdate.canonicalForm,
        confirmMerge: true
      )
      pendingLibraryMerge = nil
      self.pendingLibraryCanonicalUpdate = nil
      await refreshTodayReview()
      await refreshLibrary()
    } catch {
      // Keep the merge summary available so the user can retry.
    }
  }

  func cancelPendingLibraryMerge() {
    pendingLibraryMerge = nil
    pendingLibraryCanonicalUpdate = nil
  }

  func cancelTranslation() {
    activeTranslationID = nil
    if translationStatus == .loading {
      translationStatus = .idle
    }
  }

  func prepareTranslationPresentation(sourceApplicationName: String = "剪贴板") {
    prepareTranslationPresentation(
      title: "翻译剪贴板",
      sourceApplicationName: sourceApplicationName
    )
  }

  func prepareClipboardTranslationPresentation(
    sourceApplicationName: String = "剪贴板"
  ) -> String? {
    let clipboardText = environment.clipboard.readText()
    let sourceText =
      clipboardText.map {
        TranslationTextNormalizer.collapseWhitespace(in: $0)
      } ?? ""
    let isLongText = !sourceText.isEmpty && !Self.isWordOrShortPhrase(sourceText)

    prepareTranslationPresentation(
      title: isLongText ? "翻译长文本" : "翻译剪贴板",
      sourceApplicationName: sourceApplicationName
    )
    if isLongText {
      translationSourceText = sourceText
    }
    return clipboardText
  }

  func prepareSelectionTranslationPresentation(sourceApplicationName: String) {
    prepareTranslationPresentation(
      title: "翻译划词",
      sourceApplicationName: sourceApplicationName
    )
  }

  private func prepareTranslationPresentation(
    title: String,
    sourceApplicationName: String
  ) {
    translationSourceText = ""
    translationDraft = nil
    longTextTranslation = nil
    translationError = nil
    translationPresentationTitle = title
    translationSuggestedCanonicalForm = ""
    translationSourceApplicationName = sourceApplicationName
    pendingLearningMerge = nil
    pendingLearningAddition = nil
    translationStatus = .loading
  }

  func setSelectionEnabled(_ isEnabled: Bool) {
    selectionConfiguration.isEnabled = isEnabled
    environment.selectionConfigurationStore.save(selectionConfiguration)
    selectionDebugLog("selection setting changed: enabled=\(isEnabled)")
  }

  func setSentenceCardsEnabled(_ isEnabled: Bool) {
    isSentenceCardsEnabled = isEnabled
    environment.sentenceCardConfigurationStore.save(isEnabled)
  }

  func clearSentenceCardAdditionStatus() {
    sentenceCardAdditionStatus = nil
  }

  func setTranslationShortcut(_ shortcut: TranslationShortcutKey) {
    guard translationShortcut != shortcut else {
      return
    }
    guard onTranslationShortcutChange?(shortcut) ?? true else {
      translationShortcutRegistrationStatus = .failed(shortcut)
      selectionDebugLog("translation shortcut change rejected: key=\(shortcut.title)")
      return
    }
    translationShortcut = shortcut
    translationShortcutRegistrationStatus = .registered
    environment.shortcutStore.save(shortcut)
  }

  func setTranslationShortcutRegistrationSucceeded(_ succeeded: Bool) {
    translationShortcutRegistrationStatus =
      succeeded ? .registered : .failed(translationShortcut)
  }

  func excludeApplication(bundleIdentifier: String, displayName: String) {
    let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard
      !normalizedBundleIdentifier.isEmpty,
      !selectionConfiguration.excludes(bundleIdentifier: normalizedBundleIdentifier)
    else {
      return
    }

    let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    selectionConfiguration.excludedApplications.append(
      ExcludedApplication(
        bundleIdentifier: normalizedBundleIdentifier,
        displayName: normalizedDisplayName.isEmpty
          ? normalizedBundleIdentifier
          : normalizedDisplayName
      ))
    selectionConfiguration.excludedApplications.sort {
      $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
    }
    environment.selectionConfigurationStore.save(selectionConfiguration)
    selectionDebugLog("selection exclusion added: bundle=\(normalizedBundleIdentifier)")
  }

  func includeApplication(bundleIdentifier: String) {
    selectionConfiguration.excludedApplications.removeAll {
      $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame
    }
    environment.selectionConfigurationStore.save(selectionConfiguration)
    selectionDebugLog("selection exclusion removed: bundle=\(bundleIdentifier)")
  }

  func setTranslationPanelPosition(_ position: TranslationPanelPosition) {
    translationPanelPosition = position
    environment.panelPositionStore.save(position)
  }

  func selectTranslationProvider(_ provider: TranslationProviderKind) {
    translationProviderConfiguration.provider = provider
    environment.providerConfigurationStore.save(translationProviderConfiguration)
    isTranslationServiceConfigured = Self.hasConfiguredTranslationService(
      in: environment,
      provider: provider
    )
    connectionStatus = .idle
  }

  func updateCustomProvider(baseURL: String, model: String) {
    translationProviderConfiguration.customBaseURL = baseURL
    translationProviderConfiguration.customModel = model
    environment.providerConfigurationStore.save(translationProviderConfiguration)
    connectionStatus = .idle
  }

  func updateDeepSeekModel(_ model: DeepSeekModel) {
    translationProviderConfiguration.deepSeekModel = model
    environment.providerConfigurationStore.save(translationProviderConfiguration)
    connectionStatus = .idle
  }

  func testTranslationConnection(apiKey: String) async {
    let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedAPIKey.isEmpty else {
      connectionStatus = .failed
      return
    }

    connectionStatus = .testing

    do {
      try await environment.connectionTester.testConnection(
        configuration: translationProviderConfiguration,
        apiKey: normalizedAPIKey
      )
      try environment.apiKeyStore.saveAPIKey(
        normalizedAPIKey,
        for: translationProviderConfiguration.provider
      )
      isTranslationServiceConfigured = true
      connectionStatus = .connected
    } catch {
      connectionStatus = .failed
    }
  }

  private static func isWordOrShortPhrase(_ sourceText: String) -> Bool {
    guard Self.isWithinShortPhraseLimits(sourceText) else {
      return false
    }

    if Self.looksLikeSentence(sourceText) {
      return false
    }

    return true
  }

  private static func looksLikeSentence(_ sourceText: String) -> Bool {
    let sentenceTerminators = CharacterSet(charactersIn: ".!?。！？")
    if sourceText.unicodeScalars.contains(where: sentenceTerminators.contains) {
      return true
    }

    let tagger = NLTagger(tagSchemes: [.lexicalClass])
    tagger.string = sourceText
    tagger.setLanguage(.english, range: sourceText.startIndex..<sourceText.endIndex)

    var hasSubjectCandidate = false
    var hasSubjectBeforeVerb = false
    tagger.enumerateTags(
      in: sourceText.startIndex..<sourceText.endIndex,
      unit: .word,
      scheme: .lexicalClass,
      options: [.omitWhitespace, .omitPunctuation]
    ) { tag, _ in
      if tag == .verb, hasSubjectCandidate {
        hasSubjectBeforeVerb = true
        return false
      }
      if tag == .noun || tag == .pronoun {
        hasSubjectCandidate = true
      }
      return true
    }
    return hasSubjectBeforeVerb
  }

  private func persistLearningAddition(_ addition: LearningAddition) async throws {
    let startedAt = Date()
    environment.diagnostics.record(
      stage: .learningAdditionStarted,
      sourceApplicationIdentifier: translationSourceApplicationIdentifier
    )
    try await environment.learningStore.add(addition)
    environment.diagnostics.record(
      stage: .learningAdditionSucceeded,
      sourceApplicationIdentifier: translationSourceApplicationIdentifier,
      durationMilliseconds: Int(Date().timeIntervalSince(startedAt) * 1_000)
    )
    selectionDebugLog("add to learning persisted")
    translationDraft = nil
    translationSuggestedCanonicalForm = ""
    translationSourceApplicationName = "剪贴板"
    pendingLearningMerge = nil
    pendingLearningAddition = nil
    translationStatus = .idle
    await refreshTodayReview()
    await refreshLibrary()
  }

  private func handleLearningAdditionFailure() {
    environment.diagnostics.record(
      stage: .learningAdditionFailed,
      sourceApplicationIdentifier: translationSourceApplicationIdentifier,
      errorType: .storage
    )
    pendingLearningMerge = nil
    pendingLearningAddition = nil
    learningAdditionErrorMessage = "学习数据无法保存，请重试。"
  }
}

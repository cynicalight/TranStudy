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
  private(set) var translationStatus: TranslationStatus = .idle
  private(set) var translationError: TranslationError?
  private(set) var translationSourceText = ""
  private(set) var translationPresentationTitle = "翻译剪贴板"
  private(set) var longTextTranslation: LongTextTranslationResult?
  private(set) var learningItems: [LearningItem] = []
  private(set) var reviewQueue: [LearningItem] = []
  private(set) var isReviewAnswerVisible = false
  private(set) var isReviewRating = false
  private(set) var selectedReviewRating: ReviewRating?
  private(set) var pendingLearningMerge: LearningMergeSummary?
  private(set) var pendingLibraryMerge: LearningMergeSummary?
  private(set) var translationPanelPosition: TranslationPanelPosition
  private(set) var translationProviderConfiguration: TranslationProviderConfiguration
  private(set) var selectionConfiguration: SelectionConfiguration
  private(set) var translationShortcut: TranslationShortcutKey
  private(set) var translationShortcutRegistrationStatus: TranslationShortcutRegistrationStatus =
    .unknown
  private(set) var isSelectionContextUnavailable = false
  @ObservationIgnored var onTranslationShortcutChange: ((TranslationShortcutKey) -> Bool)?
  private var activeTranslationID: UUID?
  private var translationSuggestedCanonicalForm = ""
  private var translationSourceApplicationName = "剪贴板"
  private var pendingLearningAddition: LearningAddition?
  private var pendingLibraryCanonicalUpdate: (itemID: UUID, canonicalForm: String)?

  var currentReviewItem: LearningItem? {
    reviewQueue.first
  }

  var isLongTextTranslationPresentation: Bool {
    translationPresentationTitle == "翻译长文本"
  }

  init(environment: ApplicationEnvironment) {
    self.environment = environment
    translationPanelPosition = environment.panelPositionStore.load()
    translationProviderConfiguration = environment.providerConfigurationStore.load()
    selectionConfiguration = environment.selectionConfigurationStore.load()
    translationShortcut = environment.shortcutStore.load()
  }

  func refreshTodayReview() async {
    do {
      let now = environment.clock.now
      let summary = try await environment.learningStore.summary(at: now)
      let dueItems = try await environment.learningStore.dueItems(at: now)
      learningSummary = summary
      reviewQueue = dueItems
      isReviewAnswerVisible = false
      selectedReviewRating = nil
      lastReviewRefreshDate = now
    } catch {
      // A later ticket will expose recoverable loading errors in the review UI.
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
      let currentReviewItem,
      selectedReviewRating == nil,
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
      _ = try await environment.learningStore.recordReview(
        itemID: currentReviewItem.id,
        rating: rating,
        reviewedAt: now
      )
      selectedReviewRating = rating
      isReviewAnswerVisible = true
      learningSummary = try await environment.learningStore.summary(at: now)
      lastReviewRefreshDate = now
    } catch {
      // Keep the current card rateable when persistence fails.
    }
  }

  func advanceToNextReview() {
    guard selectedReviewRating != nil, !reviewQueue.isEmpty else {
      return
    }
    reviewQueue.removeFirst()
    isReviewAnswerVisible = false
    selectedReviewRating = nil
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
    await translateInput(snapshot.selectedText, selection: snapshot)
  }

  private func translateInput(
    _ inputText: String,
    selection: SelectionSnapshot?
  ) async {
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
    }
    selectionDebugLog(
      "translation input classified: source=\(selection == nil ? "clipboard" : "selection") selectedLength=\(sourceText.count) mode=\(isWordOrShortPhrase ? "word-or-phrase" : "long-text")"
    )

    if isWordOrShortPhrase {
      if let selection {
        isSelectionContextUnavailable = !selection.hasContext
        await translate(
          TranslationRequest(
            sourceText: sourceText,
            context: selection.translationContext,
            kind: .contextualSelection,
            targetSentence: selection.targetSentence
          ))
      } else {
        await translate(TranslationRequest(sourceText: sourceText))
      }
    } else {
      isSelectionContextUnavailable = false
      await translateLongText(sourceText)
    }
  }

  private func translate(_ request: TranslationRequest) async {
    let translationID = UUID()
    activeTranslationID = translationID
    translationSourceText = request.sourceText
    translationError = nil
    longTextTranslation = nil
    translationStatus = .loading

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
      selectionDebugLog("translation failed: errorType=\(String(reflecting: type(of: error)))")
    }
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

    do {
      let result = try await environment.translation.translateLongText(sourceText)
      try Task.checkCancellation()
      guard activeTranslationID == translationID else {
        return
      }

      activeTranslationID = nil
      longTextTranslation = result
      translationStatus = .ready
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
    isSelectionContextUnavailable = false
    await translate(request)
  }

  func canTranslateLongTextSelection(_ selectedRange: NSRange) -> Bool {
    longTextSelectionRequest(for: selectedRange) != nil
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
      if correctedCanonicalForm,
        let mergeSummary = try await environment.learningStore.mergeSummary(for: addition)
      {
        pendingLearningMerge = mergeSummary
        pendingLearningAddition = addition
        selectionDebugLog("add to learning paused: merge confirmation required")
        return
      }

      try await persistLearningAddition(addition)
    } catch {
      selectionDebugLog("add to learning failed: errorType=\(String(reflecting: type(of: error)))")
      // The translation panel keeps the draft available when persistence fails.
    }
  }

  func confirmPendingLearningMerge() async {
    guard let pendingLearningAddition else {
      return
    }

    do {
      try await persistLearningAddition(pendingLearningAddition)
    } catch {
      // The translation panel keeps the draft and merge summary available on failure.
    }
  }

  func cancelPendingLearningMerge() {
    pendingLearningMerge = nil
    pendingLearningAddition = nil
  }

  func refreshLibrary() async {
    do {
      learningItems = try await environment.learningStore.items()
    } catch {
      // A later ticket exposes recoverable library loading failures.
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

  func prepareSelectionTranslationPresentation(
    sourceApplicationName: String,
    hasContext: Bool
  ) {
    prepareTranslationPresentation(
      title: "翻译划词",
      sourceApplicationName: sourceApplicationName
    )
    isSelectionContextUnavailable = !hasContext
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
    isSelectionContextUnavailable = false
    translationStatus = .loading
  }

  func setSelectionEnabled(_ isEnabled: Bool) {
    selectionConfiguration.isEnabled = isEnabled
    environment.selectionConfigurationStore.save(selectionConfiguration)
    selectionDebugLog("selection setting changed: enabled=\(isEnabled)")
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
    try await environment.learningStore.add(addition)
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
}

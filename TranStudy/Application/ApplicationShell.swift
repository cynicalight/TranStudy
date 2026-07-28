import Foundation
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

@MainActor
@Observable
final class ApplicationShell {
  let environment: ApplicationEnvironment
  let destinations = AppDestination.allCases
  var selectedDestination: AppDestination? = .todayReview
  private(set) var learningSummary = LearningSummary.empty
  private(set) var lastReviewRefreshDate: Date?
  var translationDraft: TranslationDraft?
  private(set) var connectionStatus: TranslationConnectionStatus = .idle
  private(set) var translationStatus: TranslationStatus = .idle
  private(set) var translationSourceText = ""
  private(set) var learningItems: [LearningItem] = []
  private(set) var reviewQueue: [LearningItem] = []
  private(set) var isReviewAnswerVisible = false
  private(set) var isReviewRating = false
  private(set) var selectedReviewRating: ReviewRating?
  private(set) var pendingLearningMerge: LearningMergeSummary?
  private(set) var pendingLibraryMerge: LearningMergeSummary?
  private(set) var translationPanelPosition: TranslationPanelPosition
  private(set) var translationProviderConfiguration: TranslationProviderConfiguration
  private var activeTranslationID: UUID?
  private var translationSuggestedCanonicalForm = ""
  private var translationSourceApplicationName = "剪贴板"
  private var pendingLearningAddition: LearningAddition?
  private var pendingLibraryCanonicalUpdate: (itemID: UUID, canonicalForm: String)?

  var currentReviewItem: LearningItem? {
    reviewQueue.first
  }

  init(environment: ApplicationEnvironment) {
    self.environment = environment
    translationPanelPosition = environment.panelPositionStore.load()
    translationProviderConfiguration = environment.providerConfigurationStore.load()
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
    guard
      let sourceText = environment.clipboard.readText()?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      Self.isWordOrShortPhrase(sourceText)
    else {
      translationStatus = .failed
      return
    }

    let translationID = UUID()
    activeTranslationID = translationID
    translationSourceText = sourceText
    translationStatus = .loading

    do {
      let result = try await environment.translation.translate(
        TranslationRequest(sourceText: sourceText)
      )
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
    } catch is CancellationError {
      if activeTranslationID == translationID {
        activeTranslationID = nil
        translationStatus = .idle
      }
    } catch {
      if activeTranslationID == translationID {
        activeTranslationID = nil
        translationStatus = .failed
      }
    }
  }

  func addCurrentDraftToLearning() async {
    guard let translationDraft else {
      return
    }

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
        return
      }

      try await persistLearningAddition(addition)
    } catch {
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
    translationSourceText = ""
    translationSuggestedCanonicalForm = ""
    translationSourceApplicationName = sourceApplicationName
    pendingLearningMerge = nil
    pendingLearningAddition = nil
    translationStatus = .loading
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
    guard
      !sourceText.isEmpty,
      sourceText.count <= 160,
      !sourceText.contains(where: \.isNewline)
    else {
      return false
    }

    let words = sourceText.split(whereSeparator: \.isWhitespace)
    guard (1...8).contains(words.count) else {
      return false
    }

    let sentenceTerminators = CharacterSet(charactersIn: ".!?。！？")
    if words.count > 1,
      sourceText.unicodeScalars.contains(where: sentenceTerminators.contains)
    {
      return false
    }

    return true
  }

  private func persistLearningAddition(_ addition: LearningAddition) async throws {
    try await environment.learningStore.add(addition)
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

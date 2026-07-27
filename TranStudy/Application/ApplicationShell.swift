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
  private var activeTranslationID: UUID?

  init(environment: ApplicationEnvironment) {
    self.environment = environment
  }

  func refreshTodayReview() async {
    do {
      let summary = try await environment.learningStore.summary()
      learningSummary = summary
      lastReviewRefreshDate = environment.clock.now
    } catch {
      // A later ticket will expose recoverable loading errors in the review UI.
    }
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

    do {
      try await environment.learningStore.add(
        LearningAddition(
          draft: translationDraft,
          sourceApplicationName: "剪贴板",
          createdAt: environment.clock.now
        ))
      self.translationDraft = nil
      translationStatus = .idle
      await refreshTodayReview()
      await refreshLibrary()
    } catch {
      // The translation panel keeps the draft available when persistence fails.
    }
  }

  func refreshLibrary() async {
    do {
      learningItems = try await environment.learningStore.items()
    } catch {
      // A later ticket exposes recoverable library loading failures.
    }
  }

  func cancelTranslation() {
    activeTranslationID = nil
    if translationStatus == .loading {
      translationStatus = .idle
    }
  }

  func prepareTranslationPresentation() {
    translationSourceText = ""
    translationStatus = .loading
  }

  func testDeepSeekConnection(apiKey: String) async {
    let normalizedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalizedAPIKey.isEmpty else {
      connectionStatus = .failed
      return
    }

    connectionStatus = .testing

    do {
      try await environment.connectionTester.testConnection(apiKey: normalizedAPIKey)
      try environment.apiKeyStore.saveAPIKey(normalizedAPIKey)
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
}

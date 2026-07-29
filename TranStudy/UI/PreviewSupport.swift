#if DEBUG
  import Foundation
  import SwiftUI

  @MainActor
  enum PreviewFactory {
    static func makeShell(
      providerConfiguration: TranslationProviderConfiguration = .default
    ) -> ApplicationShell {
      ApplicationShell(
        environment: ApplicationEnvironment(
          selection: PreviewSelectionProvider(),
          clipboard: PreviewClipboardReader(text: "serendipity"),
          translation: PreviewTranslationProvider(result: PreviewFixtures.translationResult),
          learningStore: PreviewLearningStore(
            summary: PreviewFixtures.learningSummary,
            items: PreviewFixtures.learningItems
          ),
          apiKeyStore: PreviewAPIKeyStore(),
          connectionTester: PreviewConnectionTester(),
          clock: PreviewClock(),
          notifications: PreviewReviewNotifier(),
          speech: PreviewSpeechPlayer(),
          panelPositionStore: PreviewPanelPositionStore(),
          providerConfigurationStore: PreviewProviderConfigurationStore(
            configuration: providerConfiguration
          ),
          selectionConfigurationStore: PreviewSelectionConfigurationStore(),
          shortcutStore: PreviewTranslationShortcutStore()
        ))
    }

    static func rootView() -> some View {
      let shell = makeShell()

      return RootView(shell: shell, onTranslateClipboard: {})
        .frame(width: 940, height: 640)
        .task {
          await shell.refreshTodayReview()
          await shell.refreshLibrary()
        }
    }

    static func todayReviewView() -> some View {
      let shell = makeShell()

      return TodayReviewView(shell: shell)
        .frame(width: 760, height: 560)
        .task {
          await shell.refreshTodayReview()
        }
    }

    static func learningLibraryView() -> some View {
      let shell = makeShell()

      return LearningLibraryView(shell: shell)
        .frame(width: 760, height: 560)
    }

    static func translationSettingsView(
      providerConfiguration: TranslationProviderConfiguration = .default
    ) -> some View {
      TranslationSettingsView(
        shell: makeShell(providerConfiguration: providerConfiguration)
      )
      .frame(width: 760, height: 600)
    }

    static func translationPanelView() -> some View {
      let shell = makeShell()

      return TranslationPanelView(
        shell: shell,
        onDismiss: {},
        onTranslateLongTextSelection: { _ in }
      )
      .frame(height: 470)
      .task {
        await shell.translateClipboard()
      }
    }
  }

  enum PreviewFixtures {
    static let learningSummary = LearningSummary(
      dueCount: 4,
      wordCount: 28,
      sentenceCount: 6
    )

    static let learningItems = [
      LearningItem(
        id: UUID(uuidString: "23E7CBA1-FE0F-45A5-93DA-F980AE999071")!,
        sourceText: "serendipity",
        canonicalForm: "serendipity",
        pronunciation: "/ˌserənˈdɪpəti/",
        partOfSpeech: "noun",
        contextualMeaning: "意外发现美好事物的幸运",
        exampleSentence: "Finding this quiet bookstore was pure serendipity.",
        sentenceTranslation: "发现这家安静的书店纯属意外之喜。",
        sourceApplicationName: "Safari",
        createdAt: Date(timeIntervalSince1970: 1_753_632_000)
      ),
      LearningItem(
        id: UUID(uuidString: "E4ED638B-95C9-4385-A518-A309420DE00F")!,
        sourceText: "resilient",
        canonicalForm: "resilient",
        pronunciation: "/rɪˈzɪliənt/",
        partOfSpeech: "adjective",
        contextualMeaning: "有韧性的；能迅速恢复的",
        exampleSentence: "The team remained resilient after the setback.",
        sentenceTranslation: "团队在受挫后依然保持韧性。",
        sourceApplicationName: "Preview",
        createdAt: Date(timeIntervalSince1970: 1_753_545_600)
      ),
    ]

    static let translationResult = TranslationResult(
      sourceText: "serendipity",
      canonicalForm: "serendipity",
      pronunciation: "/ˌserənˈdɪpəti/",
      partOfSpeech: "noun",
      contextualMeaning: "意外发现美好事物的幸运",
      exampleSentence: "Finding this quiet bookstore was pure serendipity.",
      sentenceTranslation: "发现这家安静的书店纯属意外之喜。"
    )
  }

  private struct PreviewSelectionProvider: SelectionProviding {
    func currentSelection() async -> SelectionSnapshot? {
      nil
    }
  }

  private struct PreviewClipboardReader: ClipboardReading {
    let text: String?

    func readText() -> String? {
      text
    }
  }

  @MainActor
  private struct PreviewTranslationProvider: TranslationProviding {
    let result: TranslationResult

    func translate(_ request: TranslationRequest) async throws -> TranslationResult {
      result
    }
  }

  @MainActor
  private final class PreviewLearningStore: LearningStoring {
    private let storedSummary: LearningSummary
    private var storedItems: [LearningItem]

    init(summary: LearningSummary, items: [LearningItem]) {
      storedSummary = summary
      storedItems = items
    }

    func summary(at date: Date) async throws -> LearningSummary {
      storedSummary
    }

    func add(_ addition: LearningAddition) async throws {}

    func dueItems(at date: Date) async throws -> [LearningItem] {
      storedItems
    }

    func recordReview(
      itemID: UUID,
      rating: ReviewRating,
      reviewedAt: Date
    ) async throws -> LearningReviewResult {
      LearningReviewResult(
        itemID: itemID,
        rating: rating,
        reviewedAt: reviewedAt,
        nextReviewAt: reviewedAt.addingTimeInterval(3 * 86_400),
        intervalDays: 3
      )
    }

    func items() async throws -> [LearningItem] {
      storedItems
    }
  }

  @MainActor
  private final class PreviewAPIKeyStore: APIKeyStoring {
    func loadAPIKey(for provider: TranslationProviderKind) throws -> String? {
      nil
    }

    func saveAPIKey(_ apiKey: String, for provider: TranslationProviderKind) throws {}
  }

  @MainActor
  private struct PreviewConnectionTester: TranslationConnectionTesting {
    func testConnection(
      configuration: TranslationProviderConfiguration,
      apiKey: String
    ) async throws {}
  }

  private struct PreviewClock: DateProviding {
    var now: Date {
      Date(timeIntervalSince1970: 1_753_632_000)
    }
  }

  @MainActor
  private struct PreviewReviewNotifier: ReviewNotifying {
    func schedule(_ reminder: ReviewReminder) async throws {}
  }

  private struct PreviewSpeechPlayer: SpeechPlaying {
    func speak(_ text: String) {}
  }

  private final class PreviewPanelPositionStore: TranslationPanelPositionStoring {
    private var position = TranslationPanelPosition.topTrailing

    func load() -> TranslationPanelPosition {
      position
    }

    func save(_ position: TranslationPanelPosition) {
      self.position = position
    }
  }

  private final class PreviewProviderConfigurationStore:
    TranslationProviderConfigurationStoring
  {
    private var configuration: TranslationProviderConfiguration

    init(configuration: TranslationProviderConfiguration) {
      self.configuration = configuration
    }

    func load() -> TranslationProviderConfiguration {
      configuration
    }

    func save(_ configuration: TranslationProviderConfiguration) {
      self.configuration = configuration
    }
  }

  private final class PreviewSelectionConfigurationStore: SelectionConfigurationStoring {
    private var configuration = SelectionConfiguration.default

    func load() -> SelectionConfiguration {
      configuration
    }

    func save(_ configuration: SelectionConfiguration) {
      self.configuration = configuration
    }
  }

  private final class PreviewTranslationShortcutStore: TranslationShortcutStoring {
    private var shortcut = TranslationShortcutKey.default

    func load() -> TranslationShortcutKey {
      shortcut
    }

    func save(_ shortcut: TranslationShortcutKey) {
      self.shortcut = shortcut
    }
  }
#endif

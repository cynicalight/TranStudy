import SwiftData
import SwiftUI

@main
struct TranStudyApp: App {
  @NSApplicationDelegateAdaptor(TranStudyApplicationDelegate.self)
  private var appDelegate
  @State private var shell: ApplicationShell
  private let coordinator: ApplicationCoordinator
  private let reviewNotifier: SystemReviewNotifier

  init() {
    do {
      let learningStoreURL = try LearningStoreLocation.preparePersistentStoreURL()
      let learningStoreConfiguration = ModelConfiguration(url: learningStoreURL)
      let container = try ModelContainer(
        for: LearningRecord.self,
        LearningEncounterRecord.self,
        ReviewEventRecord.self,
        LearningCustomExampleRecord.self,
        configurations: learningStoreConfiguration
      )
      let learningStore = SwiftDataLearningStore(container: container)
      let keychainAPIKeyStore = KeychainAPIKeyStore()
      #if DEBUG
        let apiKeyStore: any APIKeyStoring = DebugEnvironmentAPIKeyStore(
          fallback: keychainAPIKeyStore
        )
      #else
        let apiKeyStore: any APIKeyStoring = keychainAPIKeyStore
      #endif
      let httpClient = URLSessionHTTPClient()
      let providerConfigurationStore = UserDefaultsTranslationProviderConfigurationStore()
      let reviewNotifier = SystemReviewNotifier()
      let translationCache = FileTranslationCacheStore()
      let diagnostics = FileDiagnosticLogStore()
      let translationService = ConfiguredTranslationService(
        configurationStore: providerConfigurationStore,
        apiKeyStore: apiKeyStore,
        httpClient: httpClient,
        cacheStore: translationCache
      )
      let shell = ApplicationShell(
        environment: .live(
          learningStore: learningStore,
          translation: translationService,
          translationCache: translationCache,
          diagnostics: diagnostics,
          apiKeyStore: apiKeyStore,
          connectionTester: translationService,
          providerConfigurationStore: providerConfigurationStore,
          notifications: reviewNotifier
        ))
      _shell = State(initialValue: shell)
      coordinator = ApplicationCoordinator(shell: shell)
      self.reviewNotifier = reviewNotifier
    } catch {
      fatalError("Unable to initialize the learning store: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup("TranStudy", id: "main") {
      RootView(
        shell: shell,
        onTranslateClipboard: {
          coordinator.presentClipboardTranslation()
        }
      )
      .tint(TranStudyDesign.accentColor)
      .environment(\.locale, shell.interfaceLanguage.locale)
      .frame(minWidth: 760, minHeight: 520)
      .background(
        NotificationRoutingBridge(
          shell: shell,
          notifier: reviewNotifier
        )
      )
      .onAppear {
        coordinator.start()
      }
      .task {
        await shell.refreshTodayReview()
        await shell.refreshLibrary()
      }
    }
    .defaultSize(width: 940, height: 640)
    .commands {
      CommandGroup(after: .appInfo) {
        Button(shell.localized("检查更新…")) {
          shell.checkForUpdates()
        }
      }

      CommandMenu(shell.localized("翻译")) {
        Button(shell.localized("翻译剪贴板")) {
          coordinator.presentClipboardTranslation()
        }
      }

      CommandGroup(after: .help) {
        Menu(shell.localized("复习快捷键")) {
          Button(shell.localized("Space：翻卡；翻卡后朗读单词")) {}
            .disabled(true)
          Button(shell.localized("1：忘记")) {}
            .disabled(true)
          Button(shell.localized("2：困难")) {}
            .disabled(true)
          Button(shell.localized("3：记得")) {}
            .disabled(true)
          Button(shell.localized("4：简单")) {}
            .disabled(true)
          Button(shell.localized("Return：下一张")) {}
            .disabled(true)
        }
      }
    }

    MenuBarExtra {
      TranStudyMenuBarView(shell: shell)
        .environment(\.locale, shell.interfaceLanguage.locale)
    } label: {
      Label("TranStudy", systemImage: "character.book.closed")
    }
    .menuBarExtraStyle(.menu)
  }
}

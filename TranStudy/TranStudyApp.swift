import AppKit
import SwiftData
import SwiftUI

@main
struct TranStudyApp: App {
  @State private var shell: ApplicationShell
  private let coordinator: ApplicationCoordinator

  init() {
    do {
      let container = try ModelContainer(for: LearningRecord.self)
      let learningStore = SwiftDataLearningStore(container: container)
      let apiKeyStore = KeychainAPIKeyStore()
      let httpClient = URLSessionHTTPClient()
      let providerConfigurationStore = UserDefaultsTranslationProviderConfigurationStore()
      let translationService = ConfiguredTranslationService(
        configurationStore: providerConfigurationStore,
        apiKeyStore: apiKeyStore,
        httpClient: httpClient,
        cacheStore: FileTranslationCacheStore()
      )
      let shell = ApplicationShell(
        environment: .live(
          learningStore: learningStore,
          translation: translationService,
          apiKeyStore: apiKeyStore,
          connectionTester: translationService,
          providerConfigurationStore: providerConfigurationStore
        ))
      _shell = State(initialValue: shell)
      coordinator = ApplicationCoordinator(shell: shell)
    } catch {
      fatalError("Unable to initialize the learning store: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView(
        shell: shell,
        onTranslateClipboard: {
          coordinator.presentClipboardTranslation()
        }
      )
      .frame(minWidth: 760, minHeight: 520)
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
      CommandMenu("翻译") {
        Button("翻译剪贴板") {
          coordinator.presentClipboardTranslation()
        }
        .keyboardShortcut(
          KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!)),
          modifiers: []
        )
      }
    }
  }
}

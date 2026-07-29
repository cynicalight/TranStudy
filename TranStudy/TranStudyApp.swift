import AppKit
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
      let container = try ModelContainer(
        for: LearningRecord.self,
        LearningEncounterRecord.self,
        ReviewEventRecord.self,
        LearningCustomExampleRecord.self
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
      CommandMenu("翻译") {
        Button("翻译剪贴板") {
          coordinator.presentClipboardTranslation()
        }
        .keyboardShortcut(
          shell.translationShortcut.keyEquivalent,
          modifiers: []
        )
      }
    }

    MenuBarExtra {
      TranStudyMenuBarView(shell: shell)
    } label: {
      Label("TranStudy", systemImage: "character.book.closed")
    }
    .menuBarExtraStyle(.menu)
  }
}

extension TranslationShortcutKey {
  fileprivate var keyEquivalent: KeyEquivalent {
    let functionKey: Int
    switch self {
    case .f1: functionKey = NSF1FunctionKey
    case .f2: functionKey = NSF2FunctionKey
    case .f3: functionKey = NSF3FunctionKey
    case .f4: functionKey = NSF4FunctionKey
    case .f5: functionKey = NSF5FunctionKey
    case .f6: functionKey = NSF6FunctionKey
    case .f7: functionKey = NSF7FunctionKey
    case .f8: functionKey = NSF8FunctionKey
    case .f9: functionKey = NSF9FunctionKey
    case .f10: functionKey = NSF10FunctionKey
    case .f11: functionKey = NSF11FunctionKey
    case .f12: functionKey = NSF12FunctionKey
    }
    return KeyEquivalent(Character(UnicodeScalar(functionKey)!))
  }
}

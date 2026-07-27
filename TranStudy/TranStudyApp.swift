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
      let translationProvider = DeepSeekTranslationProvider(
        apiKeyStore: apiKeyStore,
        httpClient: httpClient,
        model: .flash
      )
      let shell = ApplicationShell(
        environment: .live(
          learningStore: learningStore,
          translation: translationProvider,
          apiKeyStore: apiKeyStore,
          connectionTester: translationProvider
        ))
      _shell = State(initialValue: shell)
      coordinator = ApplicationCoordinator(shell: shell)
    } catch {
      fatalError("Unable to initialize the learning store: \(error)")
    }
  }

  var body: some Scene {
    WindowGroup {
      RootView(shell: shell)
        .frame(minWidth: 720, minHeight: 480)
        .onAppear {
          coordinator.start()
        }
        .task {
          await shell.refreshTodayReview()
          await shell.refreshLibrary()
        }
    }
    .commands {
      CommandMenu("翻译") {
        Button("翻译剪贴板") {
          coordinator.presentClipboardTranslation()
        }
        .keyboardShortcut(
          KeyEquivalent(Character(UnicodeScalar(NSF4FunctionKey)!)),
          modifiers: []
        )
      }
    }
  }
}

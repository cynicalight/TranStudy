@MainActor
final class ApplicationCoordinator {
  private let shortcutMonitor = GlobalShortcutMonitor()
  private let translationPanel: TranslationPanelController
  private var hasStarted = false

  init(shell: ApplicationShell) {
    translationPanel = TranslationPanelController(shell: shell)
  }

  func start() {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    shortcutMonitor.start { [weak self] in
      self?.presentClipboardTranslation()
    }
  }

  func presentClipboardTranslation() {
    translationPanel.presentClipboardTranslation()
  }
}

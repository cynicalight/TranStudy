@MainActor
final class ApplicationCoordinator {
  private let shell: ApplicationShell
  private let shortcutMonitor = GlobalShortcutMonitor()
  private let translationPanel: TranslationPanelController
  private let selectionEvents: SystemSelectionEventMonitor
  private let selectionIndicator: SelectionIndicatorController
  private let selectionInteraction: SelectionInteractionController
  private var hasStarted = false

  init(shell: ApplicationShell) {
    let translationPanel = TranslationPanelController(shell: shell)
    let selectionEvents = SystemSelectionEventMonitor()
    let selectionIndicator = SelectionIndicatorController()

    self.shell = shell
    self.translationPanel = translationPanel
    self.selectionEvents = selectionEvents
    self.selectionIndicator = selectionIndicator
    selectionInteraction = SelectionInteractionController(
      selection: shell.environment.selection,
      events: selectionEvents,
      indicator: selectionIndicator,
      onExternalInteraction: { [weak translationPanel] in
        translationPanel?.dismissForExternalInteraction()
      },
      onSelection: { [weak translationPanel] snapshot in
        selectionDebugLog("coordinator forwarding snapshot to translation panel")
        translationPanel?.presentSelectionTranslation(snapshot)
      }
    )
    shell.onTranslationShortcutChange = { [weak shortcutMonitor] shortcut in
      shortcutMonitor?.updateShortcut(shortcut) ?? false
    }
  }

  func start() {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    selectionDebugLog("application coordinator starting selection pipeline")
    let shortcutRegistered = shortcutMonitor.start(
      shortcut: shell.translationShortcut,
      handler: { [weak self] in
        self?.presentClipboardTranslation()
      }
    )
    shell.setTranslationShortcutRegistrationSucceeded(shortcutRegistered)
    selectionInteraction.start()
  }

  func presentClipboardTranslation() {
    translationPanel.presentClipboardTranslation()
  }
}

@MainActor
final class ApplicationCoordinator {
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

    self.translationPanel = translationPanel
    self.selectionEvents = selectionEvents
    self.selectionIndicator = selectionIndicator
    selectionInteraction = SelectionInteractionController(
      selection: shell.environment.selection,
      events: selectionEvents,
      indicator: selectionIndicator,
      isClipboardFallbackActive: { [weak translationPanel] in
        translationPanel?.isAwaitingClipboardExample == true
      },
      onExternalInteraction: { [weak translationPanel] in
        translationPanel?.dismissForExternalInteraction()
      },
      onClipboardCopy: { [weak translationPanel] changeCount in
        translationPanel?.authorizeNextClipboardChange(after: changeCount)
      },
      onSelection: { [weak translationPanel] snapshot in
        selectionDebugLog("coordinator forwarding snapshot to translation panel")
        translationPanel?.presentSelectionTranslation(snapshot)
      }
    )
  }

  func start() {
    guard !hasStarted else {
      return
    }

    hasStarted = true
    selectionDebugLog("application coordinator starting selection pipeline")
    shortcutMonitor.start { [weak self] in
      self?.presentClipboardTranslation()
    }
    selectionInteraction.start()
  }

  func presentClipboardTranslation() {
    translationPanel.presentClipboardTranslation()
  }
}

import AppKit
import Carbon.HIToolbox
import CoreGraphics

@MainActor
final class ApplicationCoordinator {
  private let shell: ApplicationShell
  private let shortcutMonitor = GlobalShortcutMonitor()
  private let translationPanel: TranslationPanelController
  private let selectionEvents: SystemSelectionEventMonitor
  private let selectionIndicator: SelectionIndicatorController
  private let selectionInteraction: SelectionInteractionController
  private let reviewReminderMonitor: ReviewReminderMonitor
  private var hasStarted = false
  private var clipboardShortcutTask: Task<Void, Never>?

  init(shell: ApplicationShell) {
    let translationPanel = TranslationPanelController(shell: shell)
    let selectionEvents = SystemSelectionEventMonitor()
    let selectionIndicator = SelectionIndicatorController(shell: shell)

    self.shell = shell
    self.translationPanel = translationPanel
    self.selectionEvents = selectionEvents
    self.selectionIndicator = selectionIndicator
    reviewReminderMonitor = ReviewReminderMonitor(
      now: { shell.environment.clock.now },
      configuration: { shell.reviewReminderConfiguration },
      sendReminder: { await shell.sendReviewReminderIfNeeded() }
    )
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
    shell.onReviewReminderConfigurationChange = { [weak self] in
      self?.reviewReminderMonitor.restart()
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
        self?.copySelectionAndPresentClipboardTranslation()
      }
    )
    shell.setTranslationShortcutRegistrationSucceeded(shortcutRegistered)
    selectionInteraction.start()
    reviewReminderMonitor.restart()
  }

  func presentClipboardTranslation() {
    translationPanel.presentClipboardTranslation()
  }

  private func copySelectionAndPresentClipboardTranslation() {
    clipboardShortcutTask?.cancel()
    clipboardShortcutTask = Task { @MainActor [weak self] in
      guard let self, !Task.isCancelled else {
        return
      }
      let initialChangeCount = NSPasteboard.general.changeCount
      guard Self.postCopyShortcut() else {
        return
      }
      try? await Task.sleep(for: .milliseconds(120))
      for _ in 0..<8 {
        guard !Task.isCancelled else {
          return
        }
        if NSPasteboard.general.changeCount != initialChangeCount {
          translationPanel.presentClipboardTranslation()
          return
        }
        try? await Task.sleep(for: .milliseconds(40))
      }
    }
  }

  private static func postCopyShortcut() -> Bool {
    guard
      let eventSource = CGEventSource(stateID: .hidSystemState),
      let keyDown = CGEvent(
        keyboardEventSource: eventSource,
        virtualKey: CGKeyCode(kVK_ANSI_C),
        keyDown: true
      ),
      let keyUp = CGEvent(
        keyboardEventSource: eventSource,
        virtualKey: CGKeyCode(kVK_ANSI_C),
        keyDown: false
      )
    else {
      return false
    }
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
    return true
  }
}

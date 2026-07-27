import AppKit
import SwiftUI

@MainActor
final class TranslationPanelController: NSObject, NSWindowDelegate {
  private let shell: ApplicationShell
  private var panel: NSPanel?
  private var translationTask: Task<Void, Never>?

  init(shell: ApplicationShell) {
    self.shell = shell
    super.init()
  }

  func presentClipboardTranslation() {
    translationTask?.cancel()
    shell.prepareTranslationPresentation()
    showPanel()
    translationTask = Task { [weak self] in
      guard let self else {
        return
      }
      await shell.translateClipboard()
    }
  }

  func dismiss() {
    translationTask?.cancel()
    translationTask = nil
    shell.cancelTranslation()
    panel?.close()
  }

  func windowWillClose(_ notification: Notification) {
    translationTask?.cancel()
    translationTask = nil
    shell.cancelTranslation()
    panel = nil
  }

  private func showPanel() {
    if let panel {
      panel.orderFrontRegardless()
      return
    }

    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
      styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
    panel.standardWindowButton(.zoomButton)?.isHidden = true
    panel.delegate = self
    panel.contentView = NSHostingView(
      rootView: TranslationPanelView(
        shell: shell,
        onDismiss: { [weak self] in
          self?.dismiss()
        }
      ))
    panel.center()

    self.panel = panel
    panel.orderFrontRegardless()
  }
}

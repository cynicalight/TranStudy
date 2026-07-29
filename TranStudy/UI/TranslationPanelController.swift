import AppKit
import SwiftUI

@MainActor
final class TranslationPanelController: NSObject, NSWindowDelegate {
  private let shell: ApplicationShell
  private var panel: NSPanel?
  private var translationTask: Task<Void, Never>?
  private var panelHasBeenKey = false

  init(shell: ApplicationShell) {
    self.shell = shell
    super.init()
  }

  func presentClipboardTranslation() {
    translationTask?.cancel()
    let sourceApplicationName =
      NSWorkspace.shared.frontmostApplication?.localizedName ?? "剪贴板"
    shell.prepareTranslationPresentation(sourceApplicationName: sourceApplicationName)
    showPanel()
    translationTask = Task { [weak self] in
      guard let self else {
        return
      }
      await shell.translateClipboard()
    }
  }

  func presentSelectionTranslation(_ snapshot: SelectionSnapshot) {
    selectionDebugLog(
      "present selection translation panel: app=\(snapshot.sourceApplicationName) selectedLength=\(snapshot.selectedText.count)"
    )
    translationTask?.cancel()
    shell.prepareSelectionTranslationPresentation(
      sourceApplicationName: snapshot.sourceApplicationName,
      hasContext: snapshot.hasContext
    )
    showPanel()
    translationTask = Task { [weak self] in
      guard let self else {
        return
      }
      selectionDebugLog("selection translation task started")
      await shell.translateSelection(snapshot)
      selectionDebugLog("selection translation task returned to panel controller")
    }
  }

  func dismissForExternalInteraction() {
    guard panel != nil || translationTask != nil else {
      return
    }
    selectionDebugLog("translation panel dismissed by external interaction")
    dismiss()
  }

  func dismiss() {
    selectionDebugLog("translation panel dismiss requested")
    translationTask?.cancel()
    translationTask = nil
    shell.cancelTranslation()
    panel?.close()
  }

  func windowWillClose(_ notification: Notification) {
    selectionDebugLog("translation panel window will close")
    translationTask?.cancel()
    translationTask = nil
    shell.cancelTranslation()
    panel = nil
    panelHasBeenKey = false
  }

  func windowDidBecomeKey(_ notification: Notification) {
    panelHasBeenKey = true
  }

  func windowDidResignKey(_ notification: Notification) {
    guard panelHasBeenKey else {
      return
    }
    selectionDebugLog("translation panel resigned key after interaction")
    dismiss()
  }

  private func showPanel() {
    if let panel {
      position(panel)
      panel.orderFrontRegardless()
      return
    }

    let panel = DismissibleTranslationPanel(
      contentRect: NSRect(x: 0, y: 0, width: 500, height: 470),
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
    panel.onCancel = { [weak self] in
      self?.dismiss()
    }
    panel.contentView = NSHostingView(
      rootView: TranslationPanelView(
        shell: shell,
        onDismiss: { [weak self] in
          self?.dismiss()
        },
        onTranslateLongTextSelection: { [weak self] selectedRange in
          self?.translateLongTextSelection(selectedRange)
        }
      ))
    position(panel)

    self.panel = panel
    panel.orderFrontRegardless()
  }

  private func translateLongTextSelection(_ selectedRange: NSRange) {
    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else {
        return
      }
      await shell.translateLongTextSelection(selectedRange)
    }
  }

  private func position(_ panel: NSPanel) {
    guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else {
      return
    }

    panel.setFrameOrigin(
      shell.translationPanelPosition.origin(
        panelSize: panel.frame.size,
        visibleFrame: screen.visibleFrame
      ))
  }
}

private final class DismissibleTranslationPanel: NSPanel {
  var onCancel: (() -> Void)?

  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }
}

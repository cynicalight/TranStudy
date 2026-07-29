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
    let sourceText = shell.prepareClipboardTranslationPresentation(
      sourceApplicationName: sourceApplicationName
    )
    showPanel()
    translationTask = Task { [weak self] in
      guard let self else {
        return
      }
      await shell.translateClipboard(sourceText)
    }
  }

  func presentSelectionTranslation(_ snapshot: SelectionSnapshot) {
    guard snapshot.hasContext else {
      selectionDebugLog("selection translation panel skipped: sentence context unavailable")
      return
    }
    selectionDebugLog(
      "present selection translation panel: app=\(snapshot.sourceApplicationName) selectedLength=\(snapshot.selectedText.count)"
    )
    translationTask?.cancel()
    shell.prepareSelectionTranslationPresentation(
      sourceApplicationName: snapshot.sourceApplicationName
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
      applyCurrentSizing(to: panel)
      panel.orderFrontRegardless()
      return
    }

    let panel = DismissibleTranslationPanel(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: TranslationPanelMetrics.width,
        height: TranslationPanelMetrics.defaultHeight
      ),
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
    let hostingView = NSHostingView(
      rootView: TranslationPanelView(
        shell: shell,
        onDismiss: { [weak self] in
          self?.dismiss()
        },
        onTranslateLongTextSelection: { [weak self] selectedRange in
          self?.translateLongTextSelection(selectedRange)
        },
        onContentSizeChange: { [weak self, weak panel] size, fitsContent in
          guard let self, let panel else {
            return
          }
          resize(
            panel,
            toFit: fitsContent
              ? size
              : NSSize(
                width: TranslationPanelMetrics.width,
                height: TranslationPanelMetrics.defaultHeight
              )
          )
        }
      ))
    panel.contentView = hostingView
    applyCurrentSizing(to: panel)

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

  private func applyCurrentSizing(to panel: NSPanel) {
    if shell.isLongTextTranslationPresentation, let contentView = panel.contentView {
      contentView.layoutSubtreeIfNeeded()
      resize(panel, toFit: contentView.fittingSize)
    } else {
      resize(
        panel,
        toFit: NSSize(
          width: TranslationPanelMetrics.width,
          height: TranslationPanelMetrics.defaultHeight
        )
      )
    }
    position(panel)
  }

  private func resize(_ panel: NSPanel, toFit contentSize: NSSize) {
    guard
      contentSize.width.isFinite,
      contentSize.height.isFinite,
      let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
    else {
      return
    }

    let maximumHeight = max(220, screen.visibleFrame.height - 48)
    let targetSize = NSSize(
      width: TranslationPanelMetrics.width,
      height: min(max(ceil(contentSize.height), 1), maximumHeight)
    )
    let currentContentSize = panel.contentView?.bounds.size ?? panel.contentLayoutRect.size
    guard abs(currentContentSize.height - targetSize.height) > 0.5 else {
      return
    }

    panel.setContentSize(targetSize)
    position(panel)
  }
}

private final class DismissibleTranslationPanel: NSPanel {
  var onCancel: (() -> Void)?

  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }
}

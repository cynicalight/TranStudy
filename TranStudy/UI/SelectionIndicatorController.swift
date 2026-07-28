import AppKit

@MainActor
final class SelectionIndicatorController: NSObject, SelectionIndicatorPresenting {
  private var panel: SelectionIndicatorPanel?
  private var onSelect: (() -> Void)?

  func present(_ candidate: SelectionCandidate, onSelect: @escaping () -> Void) {
    dismiss()
    self.onSelect = onSelect

    let panel = SelectionIndicatorPanel(
      contentRect: NSRect(origin: .zero, size: NSSize(width: 32, height: 32)),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let button = NSButton(
      image: NSImage(
        systemSymbolName: "character.book.closed.fill",
        accessibilityDescription: "翻译选中文本"
      ) ?? NSImage(),
      target: self,
      action: #selector(selectCurrentSelection)
    )
    button.isBordered = false
    button.bezelStyle = .circular
    button.contentTintColor = .controlAccentColor
    button.toolTip = "翻译选中文本"
    button.setAccessibilityLabel("翻译选中文本")

    let effectView = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
    effectView.material = .popover
    effectView.state = .active
    effectView.blendingMode = .behindWindow
    effectView.wantsLayer = true
    effectView.layer?.cornerRadius = 9
    effectView.layer?.masksToBounds = true
    effectView.addSubview(button)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
      button.topAnchor.constraint(equalTo: effectView.topAnchor),
      button.bottomAnchor.constraint(equalTo: effectView.bottomAnchor),
    ])
    panel.contentView = effectView

    position(panel, near: candidate.screenPosition)
    self.panel = panel
    panel.orderFrontRegardless()
  }

  func dismiss() {
    panel?.close()
    panel = nil
    onSelect = nil
  }

  @objc
  private func selectCurrentSelection() {
    let action = onSelect
    dismiss()
    action?()
  }

  private func position(_ panel: NSPanel, near point: CGPoint) {
    let screen =
      NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) })
      ?? NSScreen.main
      ?? NSScreen.screens.first
    guard let visibleFrame = screen?.visibleFrame else {
      panel.setFrameOrigin(NSPoint(x: point.x + 8, y: point.y - 40))
      return
    }

    let proposedOrigin = NSPoint(x: point.x + 8, y: point.y - panel.frame.height - 8)
    let origin = NSPoint(
      x: min(max(proposedOrigin.x, visibleFrame.minX), visibleFrame.maxX - panel.frame.width),
      y: min(max(proposedOrigin.y, visibleFrame.minY), visibleFrame.maxY - panel.frame.height)
    )
    panel.setFrameOrigin(origin)
  }
}

final class SelectionIndicatorPanel: NSPanel {
  override var canBecomeKey: Bool {
    false
  }

  override var canBecomeMain: Bool {
    false
  }
}

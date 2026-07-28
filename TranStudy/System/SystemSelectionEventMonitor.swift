import AppKit

@MainActor
final class SystemSelectionEventMonitor: SelectionEventMonitoring {
  private var globalMonitor: EventMonitorToken?
  private var localMonitor: EventMonitorToken?

  func start(handler: @escaping (SelectionInputEvent) -> Void) {
    guard globalMonitor == nil, localMonitor == nil else {
      return
    }

    let globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .leftMouseUp, .keyDown]
    ) { event in
      guard let inputEvent = Self.inputEvent(for: event) else {
        return
      }

      Task { @MainActor in
        handler(inputEvent)
      }
    }

    let localMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .keyDown]
    ) { event in
      let isIndicatorClick =
        event.type == .leftMouseDown
        && event.window is SelectionIndicatorPanel
      let inputEvent: SelectionInputEvent =
        if event.type == .keyDown, event.keyCode == 53 {
          .escape
        } else {
          .localApplicationInteraction
        }
      if !isIndicatorClick {
        handler(inputEvent)
      }
      return event
    }

    guard let globalMonitor, let localMonitor else {
      if let globalMonitor {
        NSEvent.removeMonitor(globalMonitor)
      }
      if let localMonitor {
        NSEvent.removeMonitor(localMonitor)
      }
      return
    }
    self.globalMonitor = EventMonitorToken(globalMonitor)
    self.localMonitor = EventMonitorToken(localMonitor)
  }

  deinit {
    if let globalMonitor {
      NSEvent.removeMonitor(globalMonitor.value)
    }
    if let localMonitor {
      NSEvent.removeMonitor(localMonitor.value)
    }
  }

  nonisolated private static func inputEvent(for event: NSEvent) -> SelectionInputEvent? {
    switch event.type {
    case .leftMouseDown:
      return .leftMouseDown
    case .leftMouseUp:
      return .leftMouseUp(at: NSEvent.mouseLocation)
    case .keyDown where event.keyCode == 53:
      return .escape
    case .keyDown:
      return .keyboardActivity
    default:
      return nil
    }
  }
}

private final class EventMonitorToken: @unchecked Sendable {
  let value: Any

  init(_ value: Any) {
    self.value = value
  }
}

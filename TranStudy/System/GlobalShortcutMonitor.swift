import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalShortcutMonitor {
  nonisolated(unsafe) private var eventHandler: EventHandlerRef?
  nonisolated(unsafe) private var hotKey: EventHotKeyRef?
  private var handler: (() -> Void)?
  private var shortcut: TranslationShortcutKey = .default

  deinit {
    if let hotKey {
      UnregisterEventHotKey(hotKey)
    }
    if let eventHandler {
      RemoveEventHandler(eventHandler)
    }
  }

  func start(
    shortcut: TranslationShortcutKey,
    handler: @escaping () -> Void
  ) -> Bool {
    guard eventHandler == nil else {
      return hotKey != nil
    }

    self.handler = handler
    self.shortcut = shortcut
    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let callback: EventHandlerUPP = { _, _, userData in
      guard let userData else {
        return noErr
      }

      let monitor = Unmanaged<GlobalShortcutMonitor>
        .fromOpaque(userData)
        .takeUnretainedValue()
      MainActor.assumeIsolated {
        monitor.handler?()
      }
      return noErr
    }

    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    guard status == noErr, eventHandler != nil else {
      self.handler = nil
      selectionDebugLog("global shortcut event handler failed: status=\(status)")
      return false
    }
    return registerHotKey(shortcut)
  }

  func updateShortcut(_ shortcut: TranslationShortcutKey) -> Bool {
    guard self.shortcut != shortcut else {
      return true
    }
    guard handler != nil else {
      self.shortcut = shortcut
      return true
    }

    if let hotKey {
      let status = UnregisterEventHotKey(hotKey)
      guard status == noErr else {
        selectionDebugLog(
          "global shortcut unregister failed: key=\(self.shortcut.title) status=\(status)"
        )
        return false
      }
      self.hotKey = nil
    }
    if registerHotKey(shortcut) {
      self.shortcut = shortcut
      return true
    }

    _ = registerHotKey(self.shortcut)
    return false
  }

  private func registerHotKey(_ shortcut: TranslationShortcutKey) -> Bool {
    let identifier = EventHotKeyID(
      signature: Self.signature,
      id: 1
    )
    let status = RegisterEventHotKey(
      shortcut.carbonKeyCode,
      0,
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )
    selectionDebugLog(
      "global shortcut registration: key=\(shortcut.title) status=\(status)"
    )
    let succeeded = status == noErr && hotKey != nil
    if !succeeded, let hotKey {
      UnregisterEventHotKey(hotKey)
      self.hotKey = nil
    }
    return succeeded
  }

  private static let signature: OSType = 0x5453_5444  // TSTD
}

extension TranslationShortcutKey {
  fileprivate var carbonKeyCode: UInt32 {
    switch self {
    case .f1: UInt32(kVK_F1)
    case .f2: UInt32(kVK_F2)
    case .f3: UInt32(kVK_F3)
    case .f4: UInt32(kVK_F4)
    case .f5: UInt32(kVK_F5)
    case .f6: UInt32(kVK_F6)
    case .f7: UInt32(kVK_F7)
    case .f8: UInt32(kVK_F8)
    case .f9: UInt32(kVK_F9)
    case .f10: UInt32(kVK_F10)
    case .f11: UInt32(kVK_F11)
    case .f12: UInt32(kVK_F12)
    }
  }
}

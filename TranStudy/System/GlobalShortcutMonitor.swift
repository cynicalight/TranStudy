import Carbon.HIToolbox
import Foundation

@MainActor
final class GlobalShortcutMonitor {
  private var eventHandler: EventHandlerRef?
  private var hotKey: EventHotKeyRef?
  private var handler: (() -> Void)?

  func start(handler: @escaping () -> Void) {
    guard hotKey == nil else {
      return
    }

    self.handler = handler
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

    InstallEventHandler(
      GetApplicationEventTarget(),
      callback,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    let identifier = EventHotKeyID(
      signature: Self.signature,
      id: 1
    )
    RegisterEventHotKey(
      UInt32(kVK_F4),
      0,
      identifier,
      GetApplicationEventTarget(),
      0,
      &hotKey
    )
  }

  private static let signature: OSType = 0x5453_5444  // TSTD
}

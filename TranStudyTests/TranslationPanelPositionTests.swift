import AppKit
import Foundation
import Testing

@testable import TranStudy

@MainActor
struct TranslationPanelPositionTests {
  @Test("panel position defaults to the top right and persists changes")
  func panelPositionDefaultsAndPersists() {
    let suiteName = "TranslationPanelPositionTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let store = UserDefaultsTranslationPanelPositionStore(defaults: defaults)

    #expect(store.load() == .topTrailing)

    store.save(.topLeading)

    #expect(store.load() == .topLeading)
  }

  @Test("panel positions use the visible screen frame")
  func panelPositionsUseVisibleScreenFrame() {
    let visibleFrame = NSRect(x: 100, y: 200, width: 1_200, height: 800)
    let panelSize = NSSize(width: 460, height: 360)

    #expect(
      TranslationPanelPosition.topLeading.origin(
        panelSize: panelSize,
        visibleFrame: visibleFrame
      ) == NSPoint(x: 124, y: 616)
    )
    #expect(
      TranslationPanelPosition.center.origin(
        panelSize: panelSize,
        visibleFrame: visibleFrame
      ) == NSPoint(x: 470, y: 420)
    )
    #expect(
      TranslationPanelPosition.topTrailing.origin(
        panelSize: panelSize,
        visibleFrame: visibleFrame
      ) == NSPoint(x: 816, y: 616)
    )
  }
}

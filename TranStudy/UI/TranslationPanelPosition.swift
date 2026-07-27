import AppKit

enum TranslationPanelPosition: String, CaseIterable, Identifiable {
  case topLeading
  case center
  case topTrailing

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .topLeading:
      "左上角"
    case .center:
      "中间"
    case .topTrailing:
      "右上角"
    }
  }

  func origin(
    panelSize: NSSize,
    visibleFrame: NSRect,
    margin: CGFloat = 24
  ) -> NSPoint {
    let y = visibleFrame.maxY - panelSize.height - margin

    switch self {
    case .topLeading:
      return NSPoint(x: visibleFrame.minX + margin, y: y)
    case .center:
      return NSPoint(
        x: visibleFrame.midX - panelSize.width / 2,
        y: visibleFrame.midY - panelSize.height / 2
      )
    case .topTrailing:
      return NSPoint(x: visibleFrame.maxX - panelSize.width - margin, y: y)
    }
  }
}

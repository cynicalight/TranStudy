import Foundation
import Testing

@testable import TranStudy

@MainActor
struct SelectionInteractionControllerTests {
  @Test("mouse selection shows a private indicator and captures text only after click")
  func mouseSelectionCapturesTextOnlyAfterClick() async {
    let point = CGPoint(x: 640, y: 420)
    let candidate = SelectionCandidate(
      screenPosition: point,
      sourceApplicationName: "Safari"
    )
    let snapshot = SelectionSnapshot(
      selectedText: "ran",
      targetSentence: "She ran home.",
      previousSentence: nil,
      nextSentence: nil,
      screenPosition: point,
      sourceApplicationName: "Safari"
    )
    let selection = TestSelectionProvider(candidate: candidate, snapshot: snapshot)
    let events = TestSelectionEventMonitor()
    let indicator = TestSelectionIndicator()
    var capturedSnapshots: [SelectionSnapshot] = []
    let controller = SelectionInteractionController(
      selection: selection,
      events: events,
      indicator: indicator,
      candidatePollInterval: .zero,
      candidateTimeout: .seconds(1),
      indicatorLifetime: .seconds(30)
    ) { capturedSnapshots.append($0) }

    controller.start()
    events.send(.leftMouseDown(at: CGPoint(x: point.x - 10, y: point.y), clickCount: 1))
    events.send(.leftMouseUp(at: point, clickCount: 1))
    try? await Task.sleep(for: .milliseconds(5))

    #expect(selection.candidateRequestCount == 1)
    #expect(selection.snapshotRequestCount == 0)
    #expect(indicator.presentedCandidate == candidate)

    indicator.select()
    try? await Task.sleep(for: .milliseconds(5))

    #expect(selection.snapshotRequestCount == 1)
    #expect(capturedSnapshots == [snapshot])

    events.send(.leftMouseDown(at: point, clickCount: 1))
    #expect(indicator.dismissCount > 0)
  }

  @Test("escape dismisses the selection indicator")
  func escapeDismissesSelectionIndicator() {
    let events = TestSelectionEventMonitor()
    let indicator = TestSelectionIndicator()
    let controller = SelectionInteractionController(
      selection: TestSelectionProvider(),
      events: events,
      indicator: indicator,
      candidatePollInterval: .zero,
      candidateTimeout: .seconds(1),
      indicatorLifetime: .seconds(30)
    ) { _ in }

    controller.start()
    events.send(.escape)

    #expect(indicator.dismissCount == 1)
  }

  @Test("keyboard selection never presents an indicator")
  func keyboardSelectionNeverPresentsIndicator() {
    let selection = TestSelectionProvider()
    let events = TestSelectionEventMonitor()
    let indicator = TestSelectionIndicator()
    var externalInteractionCount = 0
    let controller = SelectionInteractionController(
      selection: selection,
      events: events,
      indicator: indicator,
      candidatePollInterval: .zero,
      candidateTimeout: .seconds(1),
      indicatorLifetime: .seconds(30),
      onExternalInteraction: { externalInteractionCount += 1 },
      onSelection: { _ in }
    )

    controller.start()
    events.send(.keyboardActivity)

    #expect(selection.candidateRequestCount == 0)
    #expect(indicator.presentedCandidate == nil)
    #expect(externalInteractionCount == 1)
  }

  @Test("local app interaction dismisses only the indicator")
  func localAppInteractionDoesNotDismissTranslationPanel() {
    let events = TestSelectionEventMonitor()
    let indicator = TestSelectionIndicator()
    var externalInteractionCount = 0
    let controller = SelectionInteractionController(
      selection: TestSelectionProvider(),
      events: events,
      indicator: indicator,
      candidatePollInterval: .zero,
      candidateTimeout: .seconds(1),
      indicatorLifetime: .seconds(30),
      onExternalInteraction: { externalInteractionCount += 1 },
      onSelection: { _ in }
    )

    controller.start()
    events.send(.localApplicationInteraction)

    #expect(indicator.dismissCount == 1)
    #expect(externalInteractionCount == 0)
  }

  @Test("selection indicator expires when it is ignored")
  func selectionIndicatorExpiresWhenIgnored() async {
    let point = CGPoint(x: 640, y: 420)
    let candidate = SelectionCandidate(
      screenPosition: point,
      sourceApplicationName: "TextEdit"
    )
    let events = TestSelectionEventMonitor()
    let indicator = TestSelectionIndicator()
    let controller = SelectionInteractionController(
      selection: TestSelectionProvider(candidate: candidate),
      events: events,
      indicator: indicator,
      candidatePollInterval: .zero,
      candidateTimeout: .seconds(1),
      indicatorLifetime: .milliseconds(5)
    ) { _ in }

    controller.start()
    events.send(.leftMouseDown(at: CGPoint(x: point.x - 10, y: point.y), clickCount: 1))
    events.send(.leftMouseUp(at: point, clickCount: 1))
    try? await Task.sleep(for: .milliseconds(2))
    #expect(indicator.presentedCandidate == candidate)

    try? await Task.sleep(for: .milliseconds(10))
    #expect(indicator.presentedCandidate == nil)
  }

  @Test("mouse up without a tracked mouse gesture never presents an indicator")
  func unrelatedMouseUpNeverPresentsIndicator() async {
    let point = CGPoint(x: 640, y: 420)
    let candidate = SelectionCandidate(
      screenPosition: point,
      sourceApplicationName: "TextEdit"
    )
    let selection = TestSelectionProvider(candidate: candidate)
    let events = TestSelectionEventMonitor()
    let indicator = TestSelectionIndicator()
    let controller = SelectionInteractionController(
      selection: selection,
      events: events,
      indicator: indicator,
      candidatePollInterval: .zero,
      candidateTimeout: .seconds(1),
      indicatorLifetime: .seconds(30)
    ) { _ in }

    controller.start()
    events.send(.leftMouseUp(at: point, clickCount: 1))
    try? await Task.sleep(for: .milliseconds(5))

    #expect(selection.gestureStartCount == 0)
    #expect(selection.candidateRequestCount == 0)
    #expect(indicator.presentedCandidate == nil)
  }

  @Test("selection change dismisses a visible indicator")
  func selectionChangeDismissesVisibleIndicator() async {
    let point = CGPoint(x: 640, y: 420)
    let candidate = SelectionCandidate(
      screenPosition: point,
      sourceApplicationName: "TextEdit"
    )
    let selection = TestSelectionProvider(candidate: candidate)
    let events = TestSelectionEventMonitor()
    let indicator = TestSelectionIndicator()
    let controller = SelectionInteractionController(
      selection: selection,
      events: events,
      indicator: indicator,
      candidatePollInterval: .zero,
      candidateTimeout: .seconds(1),
      candidateValidationInterval: .milliseconds(1),
      indicatorLifetime: .seconds(30)
    ) { _ in }

    controller.start()
    events.send(.leftMouseDown(at: CGPoint(x: point.x - 10, y: point.y), clickCount: 1))
    events.send(.leftMouseUp(at: point, clickCount: 1))
    try? await Task.sleep(for: .milliseconds(5))
    #expect(indicator.presentedCandidate == candidate)

    selection.candidateIsCurrent = false
    try? await Task.sleep(for: .milliseconds(5))

    #expect(indicator.presentedCandidate == nil)
  }
}

@MainActor
private final class TestSelectionProvider: SelectionProviding {
  private let candidate: SelectionCandidate?
  private let snapshot: SelectionSnapshot?
  private(set) var candidateRequestCount = 0
  private(set) var snapshotRequestCount = 0
  private(set) var gestureStartCount = 0
  var candidateIsCurrent = true

  init(candidate: SelectionCandidate? = nil, snapshot: SelectionSnapshot? = nil) {
    self.candidate = candidate
    self.snapshot = snapshot
  }

  func beginMouseSelectionGesture() {
    gestureStartCount += 1
  }

  func selectionCandidate(at screenPosition: CGPoint) async -> SelectionCandidate? {
    candidateRequestCount += 1
    return candidate
  }

  func currentSelection() async -> SelectionSnapshot? {
    snapshotRequestCount += 1
    return snapshot
  }

  func isSelectionCandidateCurrent() async -> Bool {
    candidateIsCurrent
  }
}

@MainActor
private final class TestSelectionEventMonitor: SelectionEventMonitoring {
  private var handler: ((SelectionInputEvent) -> Void)?

  func start(handler: @escaping (SelectionInputEvent) -> Void) {
    self.handler = handler
  }

  func send(_ event: SelectionInputEvent) {
    handler?(event)
  }
}

@MainActor
private final class TestSelectionIndicator: SelectionIndicatorPresenting {
  private var onSelect: (() -> Void)?
  private(set) var presentedCandidate: SelectionCandidate?
  private(set) var dismissCount = 0

  func present(_ candidate: SelectionCandidate, onSelect: @escaping () -> Void) {
    presentedCandidate = candidate
    self.onSelect = onSelect
  }

  func dismiss() {
    dismissCount += 1
    presentedCandidate = nil
  }

  func select() {
    onSelect?()
  }
}

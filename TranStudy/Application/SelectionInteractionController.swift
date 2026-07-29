import Foundation

func selectionDebugLog(_ message: @autoclosure () -> String) {
  #if DEBUG
    print("[SelectionDebug] \(message())")
  #endif
}

enum SelectionInputEvent: Equatable, Sendable {
  case leftMouseDown
  case leftMouseUp(at: CGPoint)
  case escape
  case keyboardActivity
  case localApplicationInteraction
}

@MainActor
protocol SelectionEventMonitoring: AnyObject {
  func start(handler: @escaping (SelectionInputEvent) -> Void)
}

@MainActor
protocol SelectionIndicatorPresenting: AnyObject {
  func present(_ candidate: SelectionCandidate, onSelect: @escaping () -> Void)
  func dismiss()
}

@MainActor
final class SelectionInteractionController {
  private let selection: any SelectionProviding
  private let events: any SelectionEventMonitoring
  private let indicator: any SelectionIndicatorPresenting
  private let candidateDelay: Duration
  private let candidateValidationInterval: Duration
  private let indicatorLifetime: Duration
  private let onExternalInteraction: () -> Void
  private let onSelection: (SelectionSnapshot) -> Void
  private var candidateTask: Task<Void, Never>?
  private var candidateValidationTask: Task<Void, Never>?
  private var lifetimeTask: Task<Void, Never>?
  private var captureTask: Task<Void, Never>?
  private var hasStarted = false
  private var isTrackingMouseGesture = false

  init(
    selection: any SelectionProviding,
    events: any SelectionEventMonitoring,
    indicator: any SelectionIndicatorPresenting,
    candidateDelay: Duration = .milliseconds(80),
    candidateValidationInterval: Duration = .milliseconds(100),
    indicatorLifetime: Duration = .seconds(4),
    onExternalInteraction: @escaping () -> Void = {},
    onSelection: @escaping (SelectionSnapshot) -> Void
  ) {
    self.selection = selection
    self.events = events
    self.indicator = indicator
    self.candidateDelay = candidateDelay
    self.candidateValidationInterval = candidateValidationInterval
    self.indicatorLifetime = indicatorLifetime
    self.onExternalInteraction = onExternalInteraction
    self.onSelection = onSelection
  }

  func start() {
    guard !hasStarted else {
      selectionDebugLog("interaction controller start ignored: already started")
      return
    }

    hasStarted = true
    selectionDebugLog("interaction controller started")
    events.start { [weak self] event in
      self?.handle(event)
    }
  }

  private func handle(_ event: SelectionInputEvent) {
    selectionDebugLog("interaction received \(event)")
    switch event {
    case .leftMouseDown:
      dismissCandidate(reason: "new mouse gesture")
      onExternalInteraction()
      isTrackingMouseGesture = true
      selection.beginMouseSelectionGesture()
    case .leftMouseUp(let screenPosition):
      guard isTrackingMouseGesture else {
        selectionDebugLog("mouse up ignored: no tracked mouse down")
        return
      }
      isTrackingMouseGesture = false
      selectionDebugLog("mouse gesture ended at \(screenPosition)")
      prepareCandidate(at: screenPosition)
    case .escape, .keyboardActivity:
      isTrackingMouseGesture = false
      dismissCandidate(reason: "escape or external keyboard activity")
      onExternalInteraction()
    case .localApplicationInteraction:
      isTrackingMouseGesture = false
      dismissCandidate(reason: "local app interaction")
    }
  }

  private func prepareCandidate(at screenPosition: CGPoint) {
    dismissCandidate(reason: "prepare new candidate")
    selectionDebugLog("waiting \(candidateDelay) before reading selection")
    candidateTask = Task { [weak self] in
      guard let self else {
        return
      }

      try? await Task.sleep(for: candidateDelay)
      guard !Task.isCancelled else {
        selectionDebugLog("candidate read cancelled during delay")
        return
      }
      guard let candidate = await selection.selectionCandidate(at: screenPosition) else {
        selectionDebugLog("candidate rejected: provider returned no new selection")
        return
      }
      guard !Task.isCancelled else {
        selectionDebugLog("candidate read cancelled after provider response")
        return
      }

      selectionDebugLog(
        "candidate accepted: app=\(candidate.sourceApplicationName) position=\(candidate.screenPosition)"
      )
      indicator.present(candidate) { [weak self] in
        self?.captureSelection()
      }
      monitorCandidate()
      scheduleDismissal()
    }
  }

  private func captureSelection() {
    selectionDebugLog("indicator clicked: capturing full selection snapshot")
    candidateTask?.cancel()
    candidateValidationTask?.cancel()
    lifetimeTask?.cancel()
    indicator.dismiss()
    captureTask?.cancel()
    captureTask = Task { [weak self] in
      guard let self else {
        return
      }
      guard let snapshot = await selection.currentSelection() else {
        selectionDebugLog("snapshot capture failed: provider returned nil")
        return
      }
      guard !Task.isCancelled else {
        selectionDebugLog("snapshot capture cancelled")
        return
      }
      selectionDebugLog(
        "snapshot captured: app=\(snapshot.sourceApplicationName) selectedLength=\(snapshot.selectedText.count) targetSentenceLength=\(snapshot.targetSentence.count)"
      )
      onSelection(snapshot)
    }
  }

  private func monitorCandidate() {
    candidateValidationTask?.cancel()
    candidateValidationTask = Task { [weak self] in
      guard let self else {
        return
      }
      while !Task.isCancelled {
        try? await Task.sleep(for: candidateValidationInterval)
        guard !Task.isCancelled else {
          return
        }
        guard await selection.isSelectionCandidateCurrent() else {
          selectionDebugLog("candidate invalidated: selection changed or disappeared")
          dismissCandidate(reason: "candidate validation failed")
          return
        }
      }
    }
  }

  private func scheduleDismissal() {
    lifetimeTask?.cancel()
    lifetimeTask = Task { [weak self] in
      guard let self else {
        return
      }
      try? await Task.sleep(for: indicatorLifetime)
      guard !Task.isCancelled else {
        return
      }
      selectionDebugLog("indicator expired after \(indicatorLifetime)")
      indicator.dismiss()
    }
  }

  private func dismissCandidate(reason: String) {
    selectionDebugLog("dismiss candidate: \(reason)")
    candidateTask?.cancel()
    candidateTask = nil
    candidateValidationTask?.cancel()
    candidateValidationTask = nil
    lifetimeTask?.cancel()
    lifetimeTask = nil
    captureTask?.cancel()
    captureTask = nil
    indicator.dismiss()
  }
}

import Foundation

func selectionDebugLog(_ message: @autoclosure () -> String) {
  #if DEBUG
    print("[SelectionDebug] \(message())")
  #endif
}

enum SelectionInputEvent: Equatable, Sendable {
  case leftMouseDown(at: CGPoint, clickCount: Int)
  case leftMouseUp(at: CGPoint, clickCount: Int)
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
  private let candidatePollInterval: Duration
  private let candidateTimeout: Duration
  private let candidateValidationInterval: Duration
  private let indicatorLifetime: Duration
  private let onExternalInteraction: () -> Void
  private let onSelection: (SelectionSnapshot) -> Void
  private var candidateTask: Task<Void, Never>?
  private var candidateValidationTask: Task<Void, Never>?
  private var lifetimeTask: Task<Void, Never>?
  private var captureTask: Task<Void, Never>?
  private var hasStarted = false
  private var mouseDownPosition: CGPoint?
  private var mouseDownClickCount = 0

  init(
    selection: any SelectionProviding,
    events: any SelectionEventMonitoring,
    indicator: any SelectionIndicatorPresenting,
    candidatePollInterval: Duration = .milliseconds(50),
    candidateTimeout: Duration = .milliseconds(500),
    candidateValidationInterval: Duration = .milliseconds(100),
    indicatorLifetime: Duration = .seconds(4),
    onExternalInteraction: @escaping () -> Void = {},
    onSelection: @escaping (SelectionSnapshot) -> Void
  ) {
    self.selection = selection
    self.events = events
    self.indicator = indicator
    self.candidatePollInterval = candidatePollInterval
    self.candidateTimeout = candidateTimeout
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
    case .leftMouseDown(let screenPosition, let clickCount):
      dismissCandidate(reason: "new mouse gesture")
      onExternalInteraction()
      mouseDownPosition = screenPosition
      mouseDownClickCount = clickCount
      selection.beginMouseSelectionGesture()
    case .leftMouseUp(let screenPosition, let clickCount):
      guard let mouseDownPosition else {
        selectionDebugLog("mouse up ignored: no tracked mouse down")
        return
      }
      let dragDistance = hypot(
        screenPosition.x - mouseDownPosition.x,
        screenPosition.y - mouseDownPosition.y
      )
      let effectiveClickCount = max(mouseDownClickCount, clickCount)
      self.mouseDownPosition = nil
      mouseDownClickCount = 0
      guard dragDistance >= 3 || effectiveClickCount >= 2 else {
        selectionDebugLog(
          "mouse gesture ignored: distance=\(dragDistance) clickCount=\(effectiveClickCount)"
        )
        return
      }
      selectionDebugLog(
        "selection gesture ended: position=\(screenPosition) distance=\(dragDistance) clickCount=\(effectiveClickCount)"
      )
      prepareCandidate(at: screenPosition)
    case .escape, .keyboardActivity:
      mouseDownPosition = nil
      mouseDownClickCount = 0
      dismissCandidate(reason: "escape or external keyboard activity")
      onExternalInteraction()
    case .localApplicationInteraction:
      mouseDownPosition = nil
      mouseDownClickCount = 0
      dismissCandidate(reason: "local app interaction")
    }
  }

  private func prepareCandidate(at screenPosition: CGPoint) {
    dismissCandidate(reason: "prepare new candidate")
    selectionDebugLog(
      "polling AX selection every \(candidatePollInterval) for up to \(candidateTimeout)"
    )
    candidateTask = Task { [weak self] in
      guard let self else {
        return
      }

      let clock = ContinuousClock()
      let deadline = clock.now.advanced(by: candidateTimeout)
      var attempt = 0
      while !Task.isCancelled {
        if attempt > 0, clock.now >= deadline {
          selectionDebugLog("candidate polling timed out after \(attempt) attempts")
          return
        }
        attempt += 1
        let candidate = await selection.selectionCandidate(at: screenPosition)
        guard clock.now <= deadline else {
          selectionDebugLog(
            "candidate poll \(attempt) finished after timeout; result discarded"
          )
          return
        }
        if let candidate {
          guard !Task.isCancelled else {
            selectionDebugLog("candidate polling cancelled after provider response")
            return
          }
          selectionDebugLog(
            "candidate accepted on poll \(attempt): app=\(candidate.sourceApplicationName) position=\(candidate.screenPosition)"
          )
          indicator.present(candidate) { [weak self] in
            self?.captureSelection()
          }
          monitorCandidate()
          scheduleDismissal()
          return
        }
        guard clock.now < deadline else {
          selectionDebugLog("candidate polling timed out after \(attempt) attempts")
          return
        }
        selectionDebugLog("candidate poll \(attempt) returned no selection; retrying")
        try? await Task.sleep(for: candidatePollInterval)
      }
      selectionDebugLog("candidate polling cancelled")
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

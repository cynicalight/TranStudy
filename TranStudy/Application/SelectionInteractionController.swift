import Foundation

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
      return
    }

    hasStarted = true
    events.start { [weak self] event in
      self?.handle(event)
    }
  }

  private func handle(_ event: SelectionInputEvent) {
    switch event {
    case .leftMouseDown:
      dismissCandidate()
      onExternalInteraction()
      isTrackingMouseGesture = true
      selection.beginMouseSelectionGesture()
    case .leftMouseUp(let screenPosition):
      guard isTrackingMouseGesture else {
        return
      }
      isTrackingMouseGesture = false
      prepareCandidate(at: screenPosition)
    case .escape, .keyboardActivity:
      isTrackingMouseGesture = false
      dismissCandidate()
      onExternalInteraction()
    case .localApplicationInteraction:
      isTrackingMouseGesture = false
      dismissCandidate()
    }
  }

  private func prepareCandidate(at screenPosition: CGPoint) {
    dismissCandidate()
    candidateTask = Task { [weak self] in
      guard let self else {
        return
      }

      try? await Task.sleep(for: candidateDelay)
      guard !Task.isCancelled else {
        return
      }
      guard let candidate = await selection.selectionCandidate(at: screenPosition) else {
        return
      }
      guard !Task.isCancelled else {
        return
      }

      indicator.present(candidate) { [weak self] in
        self?.captureSelection()
      }
      monitorCandidate()
      scheduleDismissal()
    }
  }

  private func captureSelection() {
    candidateTask?.cancel()
    candidateValidationTask?.cancel()
    lifetimeTask?.cancel()
    indicator.dismiss()
    captureTask?.cancel()
    captureTask = Task { [weak self] in
      guard
        let self,
        let snapshot = await selection.currentSelection(),
        !Task.isCancelled
      else {
        return
      }
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
          dismissCandidate()
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
      indicator.dismiss()
    }
  }

  private func dismissCandidate() {
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

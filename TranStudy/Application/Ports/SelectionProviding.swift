import Foundation

struct SelectionCandidate: Equatable, Sendable {
  let screenPosition: CGPoint
  let sourceApplicationName: String
  let sourceApplicationIdentifier: String?

  init(
    screenPosition: CGPoint,
    sourceApplicationName: String,
    sourceApplicationIdentifier: String? = nil
  ) {
    self.screenPosition = screenPosition
    self.sourceApplicationName = sourceApplicationName
    self.sourceApplicationIdentifier = sourceApplicationIdentifier
  }
}

struct SelectionSnapshot: Equatable, Sendable {
  let selectedText: String
  let targetSentence: String?
  let previousSentence: String?
  let nextSentence: String?
  let screenPosition: CGPoint
  let sourceApplicationName: String
  let sourceApplicationIdentifier: String?

  init(
    selectedText: String,
    targetSentence: String?,
    previousSentence: String?,
    nextSentence: String?,
    screenPosition: CGPoint,
    sourceApplicationName: String,
    sourceApplicationIdentifier: String? = nil
  ) {
    self.selectedText = selectedText
    self.targetSentence = targetSentence
    self.previousSentence = previousSentence
    self.nextSentence = nextSentence
    self.screenPosition = screenPosition
    self.sourceApplicationName = sourceApplicationName
    self.sourceApplicationIdentifier = sourceApplicationIdentifier
  }

  var hasContext: Bool {
    targetSentence?.isEmpty == false
  }

  var translationContext: String? {
    guard let targetSentence, !targetSentence.isEmpty else {
      return nil
    }
    var sections: [String] = []
    if let previousSentence, !previousSentence.isEmpty {
      sections.append("Previous sentence:\n\(previousSentence)")
    }
    sections.append("Target sentence:\n\(targetSentence)")
    if let nextSentence, !nextSentence.isEmpty {
      sections.append("Next sentence:\n\(nextSentence)")
    }
    return sections.joined(separator: "\n\n")
  }
}

@MainActor
protocol SelectionProviding {
  func beginMouseSelectionGesture()
  func selectionCandidate(at screenPosition: CGPoint) async -> SelectionCandidate?
  func isSelectionCandidateCurrent() async -> Bool
  func currentSelection() async -> SelectionSnapshot?
}

extension SelectionProviding {
  func beginMouseSelectionGesture() {}

  func selectionCandidate(at screenPosition: CGPoint) async -> SelectionCandidate? {
    nil
  }

  func isSelectionCandidateCurrent() async -> Bool {
    false
  }
}

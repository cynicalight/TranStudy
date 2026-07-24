struct SelectionSnapshot: Equatable, Sendable {
  let selectedText: String
  let sourceApplicationName: String
}

protocol SelectionProviding {
  func currentSelection() async -> SelectionSnapshot?
}

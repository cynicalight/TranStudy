@MainActor
protocol LoginItemControlling {
  var isEnabled: Bool { get }
  func setEnabled(_ isEnabled: Bool) throws
}

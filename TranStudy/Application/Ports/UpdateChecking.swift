@MainActor
protocol UpdateChecking: AnyObject {
  var automaticallyChecksForUpdates: Bool { get set }
  var canCheckForUpdates: Bool { get }

  func checkForUpdates()
}

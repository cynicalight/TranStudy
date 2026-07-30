@MainActor
protocol AccessibilityAuthorizing {
  var authorizationStatus: PreparationAuthorizationStatus { get }
  func requestAuthorization()
}

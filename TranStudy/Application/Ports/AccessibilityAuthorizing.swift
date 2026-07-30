enum PreparationAuthorizationStatus: Equatable {
  case notDetermined
  case authorized
  case denied
}

@MainActor
protocol AccessibilityAuthorizing {
  var authorizationStatus: PreparationAuthorizationStatus { get }
  func requestAuthorization()
}

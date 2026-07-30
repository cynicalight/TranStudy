import ApplicationServices

@MainActor
struct SystemAccessibilityAuthorizer: AccessibilityAuthorizing {
  var authorizationStatus: PreparationAuthorizationStatus {
    AXIsProcessTrusted() ? .authorized : .denied
  }

  func requestAuthorization() {
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
  }
}

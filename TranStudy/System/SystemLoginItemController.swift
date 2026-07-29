import ServiceManagement

@MainActor
struct SystemLoginItemController: LoginItemControlling {
  var isEnabled: Bool {
    switch SMAppService.mainApp.status {
    case .enabled:
      true
    case .notFound, .notRegistered, .requiresApproval:
      false
    @unknown default:
      false
    }
  }

  func setEnabled(_ isEnabled: Bool) throws {
    if isEnabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}

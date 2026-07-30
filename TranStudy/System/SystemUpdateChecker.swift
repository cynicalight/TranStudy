import Sparkle

@MainActor
final class SystemUpdateChecker: UpdateChecking {
  private let updaterController: SPUStandardUpdaterController

  init() {
    updaterController = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: nil,
      userDriverDelegate: nil
    )
  }

  var automaticallyChecksForUpdates: Bool {
    get {
      updaterController.updater.automaticallyChecksForUpdates
    }
    set {
      updaterController.updater.automaticallyChecksForUpdates = newValue
    }
  }

  var canCheckForUpdates: Bool {
    updaterController.updater.canCheckForUpdates
  }

  func checkForUpdates() {
    updaterController.updater.checkForUpdates()
  }
}

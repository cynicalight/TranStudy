import Foundation

final class UserDefaultsPreparationStateStore: PreparationStateStoring {
  private enum Key {
    static let hasCompletedInitialFlow = "preparation.hasCompletedInitialFlow"
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func loadHasCompletedInitialFlow() -> Bool {
    defaults.bool(forKey: Key.hasCompletedInitialFlow)
  }

  func saveHasCompletedInitialFlow(_ hasCompleted: Bool) {
    defaults.set(hasCompleted, forKey: Key.hasCompletedInitialFlow)
  }
}

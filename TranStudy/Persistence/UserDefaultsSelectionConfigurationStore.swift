import Foundation

struct UserDefaultsSelectionConfigurationStore: SelectionConfigurationStoring {
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "selection-configuration-v1"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> SelectionConfiguration {
    guard
      let data = defaults.data(forKey: key),
      let configuration = try? JSONDecoder().decode(SelectionConfiguration.self, from: data)
    else {
      return .default
    }
    return configuration
  }

  func save(_ configuration: SelectionConfiguration) {
    guard let data = try? JSONEncoder().encode(configuration) else {
      return
    }
    defaults.set(data, forKey: key)
  }
}

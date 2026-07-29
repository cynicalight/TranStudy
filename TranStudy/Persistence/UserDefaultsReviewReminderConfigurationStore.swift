import Foundation

struct UserDefaultsReviewReminderConfigurationStore:
  ReviewReminderConfigurationStoring
{
  private let defaults: UserDefaults
  private let key: String

  init(
    defaults: UserDefaults = .standard,
    key: String = "review-reminder-configuration-v1"
  ) {
    self.defaults = defaults
    self.key = key
  }

  func load() -> ReviewReminderConfiguration {
    guard
      let data = defaults.data(forKey: key),
      let configuration = try? JSONDecoder().decode(
        ReviewReminderConfiguration.self,
        from: data
      )
    else {
      return .default
    }
    return configuration
  }

  func save(_ configuration: ReviewReminderConfiguration) {
    guard let data = try? JSONEncoder().encode(configuration) else {
      return
    }
    defaults.set(data, forKey: key)
  }
}

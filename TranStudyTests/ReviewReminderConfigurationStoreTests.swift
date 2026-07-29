import Foundation
import Testing

@testable import TranStudy

struct ReviewReminderConfigurationStoreTests {
  @Test("review reminders are disabled by default")
  func reviewRemindersAreDisabledByDefault() {
    let suiteName = "ReviewReminderConfigurationStoreTests.default"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let store = UserDefaultsReviewReminderConfigurationStore(defaults: defaults)

    #expect(store.load() == .default)
    #expect(store.load().isEnabled == false)
  }

  @Test("review reminder time persists")
  func reviewReminderTimePersists() {
    let suiteName = "ReviewReminderConfigurationStoreTests.persistence"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let store = UserDefaultsReviewReminderConfigurationStore(defaults: defaults)
    let configuration = ReviewReminderConfiguration(
      isEnabled: true,
      hour: 18,
      minute: 30
    )

    store.save(configuration)

    #expect(store.load() == configuration)
  }
}

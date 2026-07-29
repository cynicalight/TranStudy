struct ReviewReminderConfiguration: Codable, Equatable, Sendable {
  var isEnabled: Bool
  var hour: Int
  var minute: Int

  static let `default` = ReviewReminderConfiguration(
    isEnabled: false,
    hour: 9,
    minute: 0
  )
}

protocol ReviewReminderConfigurationStoring {
  func load() -> ReviewReminderConfiguration
  func save(_ configuration: ReviewReminderConfiguration)
}

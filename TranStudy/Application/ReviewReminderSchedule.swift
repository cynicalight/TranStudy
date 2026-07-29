import Foundation

struct ReviewReminderSchedule {
  private let calendar: Calendar

  init(calendar: Calendar = .autoupdatingCurrent) {
    self.calendar = calendar
  }

  func nextDate(
    after date: Date,
    configuration: ReviewReminderConfiguration
  ) -> Date? {
    calendar.nextDate(
      after: date,
      matching: DateComponents(
        hour: configuration.hour,
        minute: configuration.minute
      ),
      matchingPolicy: .nextTime
    )
  }
}

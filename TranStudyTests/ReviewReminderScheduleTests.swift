import Foundation
import Testing

@testable import TranStudy

struct ReviewReminderScheduleTests {
  @Test("next reminder uses the selected local time")
  func nextReminderUsesSelectedLocalTime() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = try #require(
      calendar.date(
        from: DateComponents(
          year: 2026,
          month: 7,
          day: 29,
          hour: 8,
          minute: 0
        ))
    )
    let configuration = ReviewReminderConfiguration(
      isEnabled: true,
      hour: 18,
      minute: 30
    )

    let nextDate = ReviewReminderSchedule(calendar: calendar).nextDate(
      after: now,
      configuration: configuration
    )

    #expect(
      nextDate
        == calendar.date(
          from: DateComponents(
            year: 2026,
            month: 7,
            day: 29,
            hour: 18,
            minute: 30
          )))
  }
}

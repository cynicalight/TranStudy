import Foundation
import Testing

@testable import TranStudy

@MainActor
struct ReviewReminderMonitorTests {
  @Test("enabled monitor waits, sends, and schedules the following day")
  func enabledMonitorWaitsSendsAndReschedules() async {
    let calendar = Calendar(identifier: .gregorian)
    var now = Date(timeIntervalSince1970: 1_735_729_200)
    let waiter = RecordingReviewReminderWaiter()
    var sendCount = 0
    let monitor = ReviewReminderMonitor(
      waiter: waiter,
      now: { now },
      configuration: {
        ReviewReminderConfiguration(isEnabled: true, hour: 9, minute: 0)
      },
      sendReminder: {
        sendCount += 1
        now = calendar.date(byAdding: .day, value: 1, to: now)!
      }
    )

    monitor.restart()
    await waiter.releaseNextWait()
    await Task.yield()
    await Task.yield()

    #expect(sendCount == 1)
    #expect(waiter.requestedDates.count == 2)
    #expect(
      calendar.isDate(
        waiter.requestedDates[1],
        inSameDayAs: calendar.date(
          byAdding: .day,
          value: 1,
          to: waiter.requestedDates[0]
        )!
      )
    )
  }

  @Test("restart cancels the old wait and applies changed settings")
  func restartAppliesChangedSettings() async {
    let waiter = RecordingReviewReminderWaiter()
    var configuration = ReviewReminderConfiguration(
      isEnabled: true,
      hour: 9,
      minute: 0
    )
    let monitor = ReviewReminderMonitor(
      waiter: waiter,
      now: { Date(timeIntervalSince1970: 1_735_729_200) },
      configuration: { configuration },
      sendReminder: {}
    )

    monitor.restart()
    await Task.yield()
    configuration.hour = 15
    monitor.restart()
    await Task.yield()

    #expect(waiter.requestedDates.count == 2)
    #expect(
      Calendar.current.component(.hour, from: waiter.requestedDates[0]) == 9
    )
    #expect(
      Calendar.current.component(.hour, from: waiter.requestedDates[1]) == 15
    )
    #expect(waiter.cancellationCount == 1)
  }
}

@MainActor
private final class RecordingReviewReminderWaiter: ReviewReminderWaiting {
  private(set) var requestedDates: [Date] = []
  private(set) var cancellationCount = 0
  private var continuations: [CheckedContinuation<Void, any Error>] = []

  func wait(until date: Date) async throws {
    requestedDates.append(date)
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        continuations.append(continuation)
      }
    } onCancel: {
      Task { @MainActor [weak self] in
        guard let self, !continuations.isEmpty else {
          return
        }
        cancellationCount += 1
        continuations.removeFirst().resume(throwing: CancellationError())
      }
    }
  }

  func releaseNextWait() async {
    while continuations.isEmpty {
      await Task.yield()
    }
    continuations.removeFirst().resume()
  }
}

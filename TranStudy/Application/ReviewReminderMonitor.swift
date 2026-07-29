import Foundation

@MainActor
protocol ReviewReminderWaiting {
  func wait(until date: Date) async throws
}

@MainActor
struct SystemReviewReminderWaiter: ReviewReminderWaiting {
  func wait(until date: Date) async throws {
    let delay = max(0, date.timeIntervalSinceNow)
    try await Task.sleep(for: .seconds(delay))
  }
}

@MainActor
final class ReviewReminderMonitor {
  private let waiter: any ReviewReminderWaiting
  private let now: () -> Date
  private let configuration: () -> ReviewReminderConfiguration
  private let sendReminder: () async -> Void
  private var task: Task<Void, Never>?

  init(
    waiter: any ReviewReminderWaiting = SystemReviewReminderWaiter(),
    now: @escaping () -> Date,
    configuration: @escaping () -> ReviewReminderConfiguration,
    sendReminder: @escaping () async -> Void
  ) {
    self.waiter = waiter
    self.now = now
    self.configuration = configuration
    self.sendReminder = sendReminder
  }

  func restart() {
    task?.cancel()
    let configuration = configuration()
    guard
      configuration.isEnabled,
      let nextDate = ReviewReminderSchedule().nextDate(
        after: now(),
        configuration: configuration
      )
    else {
      task = nil
      return
    }

    task = Task { @MainActor [weak self] in
      guard let self else {
        return
      }
      do {
        try await waiter.wait(until: nextDate)
      } catch {
        return
      }
      guard !Task.isCancelled else {
        return
      }
      await sendReminder()
      restart()
    }
  }
}

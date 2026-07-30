import AppKit
import Foundation
import Testing
import UserNotifications

@testable import TranStudy

@MainActor
struct ApplicationLifecycleTests {
  @Test("closing the last main window keeps the application running")
  func closingLastWindowKeepsApplicationRunning() {
    let delegate = TranStudyApplicationDelegate()

    #expect(
      delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared)
        == false
    )
  }

  @Test("review notification body includes the current due count")
  func reviewNotificationBodyIncludesCurrentDueCount() {
    let reminder = ReviewReminder(date: Date(), dueCount: 7)

    #expect(reminder.notificationBody == "今天有 7 张卡片待复习。")
  }

  @Test("authorized notification scheduling creates one current-count request")
  func authorizedNotificationSchedulingCreatesOneRequest() async throws {
    let center = TestReviewNotificationCenter()
    let notifier = SystemReviewNotifier(center: center)

    try await notifier.replaceScheduledReminder(
      with: ReviewReminder(
        date: Date().addingTimeInterval(1),
        dueCount: 7
      ))

    let request = try #require(center.addedRequest)
    #expect(request.identifier == SystemReviewNotifier.requestIdentifier)
    #expect(request.content.body == "今天有 7 张卡片待复习。")
    let trigger = try #require(request.trigger as? UNTimeIntervalNotificationTrigger)
    #expect(trigger.repeats == false)
  }

  @Test("review notification responses route only the review request")
  func reviewNotificationResponsesRouteOnlyReviewRequest() {
    let notifier = SystemReviewNotifier(center: TestReviewNotificationCenter())
    var routeCount = 0
    notifier.onReviewRequested = {
      routeCount += 1
    }

    notifier.handleResponse(identifier: "another-notification")
    notifier.handleResponse(identifier: SystemReviewNotifier.requestIdentifier)

    #expect(routeCount == 1)
  }
}

@MainActor
private final class TestReviewNotificationCenter: ReviewNotificationCenterClient {
  private(set) var addedRequest: UNNotificationRequest?

  func setDelegate(_ delegate: UNUserNotificationCenterDelegate) {}

  func authorizationStatus() async -> PreparationAuthorizationStatus {
    .authorized
  }

  func requestAuthorization() async throws -> Bool {
    true
  }

  func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
    addedRequest = nil
  }

  func add(_ request: UNNotificationRequest) async throws {
    addedRequest = request
  }
}

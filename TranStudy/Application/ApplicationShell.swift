import Foundation
import Observation

@MainActor
@Observable
final class ApplicationShell {
  let environment: ApplicationEnvironment
  let destinations = AppDestination.allCases
  var selectedDestination: AppDestination? = .todayReview
  private(set) var learningSummary = LearningSummary.empty
  private(set) var lastReviewRefreshDate: Date?

  init(environment: ApplicationEnvironment) {
    self.environment = environment
  }

  func refreshTodayReview() async {
    do {
      let summary = try await environment.learningStore.summary()
      learningSummary = summary
      lastReviewRefreshDate = environment.clock.now
    } catch {
      // A later ticket will expose recoverable loading errors in the review UI.
    }
  }
}

import Foundation

struct ReviewReminder: Equatable, Sendable {
  let date: Date
  let dueCount: Int
}

@MainActor
protocol ReviewNotifying {
  func schedule(_ reminder: ReviewReminder) async throws
}

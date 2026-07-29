import Foundation

struct ReviewReminder: Equatable, Sendable {
  let date: Date
  let dueCount: Int

  var notificationBody: String {
    "今天有 \(dueCount) 张卡片待复习。"
  }
}

@MainActor
protocol ReviewNotifying {
  func replaceScheduledReminder(with reminder: ReviewReminder?) async throws
}

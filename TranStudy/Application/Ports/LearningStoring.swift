struct LearningSummary: Equatable, Sendable {
  let dueCount: Int
  let wordCount: Int
  let sentenceCount: Int

  static let empty = LearningSummary(
    dueCount: 0,
    wordCount: 0,
    sentenceCount: 0
  )
}

@MainActor
protocol LearningStoring {
  func summary() async throws -> LearningSummary
}

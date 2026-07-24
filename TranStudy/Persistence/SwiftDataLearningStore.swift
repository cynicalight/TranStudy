import SwiftData

@MainActor
final class SwiftDataLearningStore: LearningStoring {
  private let context: ModelContext

  init(container: ModelContainer) {
    context = ModelContext(container)
  }

  func summary() async throws -> LearningSummary {
    let recordCount = try context.fetchCount(FetchDescriptor<LearningRecord>())

    return LearningSummary(
      dueCount: 0,
      wordCount: recordCount,
      sentenceCount: 0
    )
  }
}

import Foundation
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

  func add(_ addition: LearningAddition) async throws {
    let draft = addition.draft
    let record = LearningRecord(
      createdAt: addition.createdAt,
      sourceText: draft.sourceText,
      canonicalForm: draft.canonicalForm,
      pronunciation: draft.pronunciation,
      partOfSpeech: draft.partOfSpeech,
      contextualMeaning: draft.contextualMeaning,
      exampleSentence: draft.exampleSentence,
      sentenceTranslation: draft.sentenceTranslation,
      sourceApplicationName: addition.sourceApplicationName
    )

    context.insert(record)
    try context.save()
  }

  func items() async throws -> [LearningItem] {
    var descriptor = FetchDescriptor<LearningRecord>(
      sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    descriptor.includePendingChanges = true

    return try context.fetch(descriptor).map { record in
      LearningItem(
        id: record.id,
        sourceText: record.sourceText,
        canonicalForm: record.canonicalForm,
        pronunciation: record.pronunciation,
        partOfSpeech: record.partOfSpeech,
        contextualMeaning: record.contextualMeaning,
        exampleSentence: record.exampleSentence,
        sentenceTranslation: record.sentenceTranslation,
        sourceApplicationName: record.sourceApplicationName,
        createdAt: record.createdAt
      )
    }
  }
}

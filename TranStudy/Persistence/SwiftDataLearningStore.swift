import Foundation
import SwiftData

enum LearningStoreError: Error {
  case emptyCanonicalForm
}

@MainActor
final class SwiftDataLearningStore: LearningStoring {
  private let context: ModelContext

  init(container: ModelContainer) {
    context = ModelContext(container)
  }

  func summary() async throws -> LearningSummary {
    let recordCount = try consolidatedRecords().count

    return LearningSummary(
      dueCount: 0,
      wordCount: recordCount,
      sentenceCount: 0
    )
  }

  func add(_ addition: LearningAddition) async throws {
    let draft = addition.draft
    let normalizedForm = NormalizedCanonicalForm(draft.canonicalForm).value
    guard !normalizedForm.isEmpty else {
      throw LearningStoreError.emptyCanonicalForm
    }
    let records = try consolidatedRecords()

    if let existingRecord = records.first(where: {
      normalizedCanonicalForm(for: $0) == normalizedForm
    }) {
      let shouldUpdateLatestSnapshot =
        addition.createdAt >= effectiveLastEncounteredAt(for: existingRecord)
      backfillLegacyEncounterIfNeeded(existingRecord)
      existingRecord.encounters.append(makeEncounter(from: addition))
      existingRecord.lastEncounteredAt = max(existingRecord.lastEncounteredAt, addition.createdAt)
      existingRecord.nextReviewAt = earlierDate(
        existingRecord.nextReviewAt,
        addition.nextReviewAt
      )
      existingRecord.isPaused = existingRecord.isPaused && addition.isPaused
      if shouldUpdateLatestSnapshot {
        updateLatestSnapshot(of: existingRecord, from: addition)
      }
      try context.save()
      return
    }

    let record = LearningRecord(
      createdAt: addition.createdAt,
      sourceText: draft.sourceText,
      canonicalForm: draft.canonicalForm.trimmingCharacters(in: .whitespacesAndNewlines),
      pronunciation: draft.pronunciation,
      partOfSpeech: draft.partOfSpeech,
      contextualMeaning: draft.contextualMeaning,
      exampleSentence: draft.exampleSentence,
      sentenceTranslation: draft.sentenceTranslation,
      sourceApplicationName: addition.sourceApplicationName,
      nextReviewAt: addition.nextReviewAt,
      isPaused: addition.isPaused
    )
    record.encounters.append(makeEncounter(from: addition))

    context.insert(record)
    try context.save()
  }

  func mergeSummary(for addition: LearningAddition) async throws -> LearningMergeSummary? {
    let normalizedForm = NormalizedCanonicalForm(addition.draft.canonicalForm).value
    let records = try consolidatedRecords()
    guard
      let existingRecord = records.first(where: {
        normalizedCanonicalForm(for: $0) == normalizedForm
      })
    else {
      return nil
    }

    return LearningMergeSummary(
      existingItemID: existingRecord.id,
      canonicalForm: existingRecord.canonicalForm,
      existingEncounterCount: max(1, existingRecord.encounters.count),
      incomingSourceText: addition.draft.sourceText
    )
  }

  func updateCanonicalForm(
    itemID: UUID,
    canonicalForm: String,
    confirmMerge: Bool
  ) async throws -> LearningCanonicalUpdateResult {
    let trimmedCanonicalForm = canonicalForm.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedForm = NormalizedCanonicalForm(trimmedCanonicalForm).value
    guard !normalizedForm.isEmpty else {
      return .updated
    }

    let records = try consolidatedRecords()
    guard let sourceRecord = records.first(where: { $0.id == itemID }) else {
      return .updated
    }

    if normalizedCanonicalForm(for: sourceRecord) == normalizedForm {
      sourceRecord.canonicalForm = trimmedCanonicalForm
      sourceRecord.normalizedCanonicalForm = normalizedForm
      try context.save()
      return .updated
    }

    guard
      let targetRecord = records.first(where: {
        $0.id != itemID && normalizedCanonicalForm(for: $0) == normalizedForm
      })
    else {
      sourceRecord.canonicalForm = trimmedCanonicalForm
      sourceRecord.normalizedCanonicalForm = normalizedForm
      try context.save()
      return .updated
    }

    let mergeSummary = LearningMergeSummary(
      existingItemID: targetRecord.id,
      canonicalForm: targetRecord.canonicalForm,
      existingEncounterCount: max(1, targetRecord.encounters.count),
      incomingSourceText: sourceRecord.sourceText
    )
    guard confirmMerge else {
      return .requiresConfirmation(mergeSummary)
    }

    merge(sourceRecord, into: targetRecord)
    try context.save()
    return .merged
  }

  func items() async throws -> [LearningItem] {
    try consolidatedRecords()
      .sorted { effectiveLastEncounteredAt(for: $0) > effectiveLastEncounteredAt(for: $1) }
      .map { record in
        let encounters = encounterItems(for: record)

        return LearningItem(
          id: record.id,
          sourceText: record.sourceText,
          canonicalForm: record.canonicalForm,
          pronunciation: record.pronunciation,
          partOfSpeech: record.partOfSpeech,
          contextualMeaning: record.contextualMeaning,
          exampleSentence: record.exampleSentence,
          sentenceTranslation: record.sentenceTranslation,
          sourceApplicationName: record.sourceApplicationName,
          createdAt: record.createdAt,
          encounters: encounters,
          nextReviewAt: record.nextReviewAt,
          isPaused: record.isPaused
        )
      }
  }

  private func consolidatedRecords() throws -> [LearningRecord] {
    var descriptor = FetchDescriptor<LearningRecord>()
    descriptor.includePendingChanges = true
    let records = try context.fetch(descriptor)
    let groupedRecords = Dictionary(grouping: records) {
      normalizedCanonicalForm(for: $0)
    }
    var didMerge = false

    for (normalizedForm, duplicates) in groupedRecords
    where !normalizedForm.isEmpty && duplicates.count > 1 {
      let orderedDuplicates = duplicates.sorted { $0.createdAt < $1.createdAt }
      guard let targetRecord = orderedDuplicates.first else {
        continue
      }

      for sourceRecord in orderedDuplicates.dropFirst() {
        merge(sourceRecord, into: targetRecord)
        didMerge = true
      }
    }

    if didMerge {
      try context.save()
      return try context.fetch(descriptor)
    }
    return records
  }

  private func effectiveLastEncounteredAt(for record: LearningRecord) -> Date {
    record.encounters.map(\.encounteredAt).max() ?? record.createdAt
  }

  private func normalizedCanonicalForm(for record: LearningRecord) -> String {
    if !record.normalizedCanonicalForm.isEmpty {
      return record.normalizedCanonicalForm
    }
    return NormalizedCanonicalForm(record.canonicalForm).value
  }

  private func makeEncounter(from addition: LearningAddition) -> LearningEncounterRecord {
    let draft = addition.draft
    return LearningEncounterRecord(
      sourceText: draft.sourceText,
      pronunciation: draft.pronunciation,
      partOfSpeech: draft.partOfSpeech,
      contextualMeaning: draft.contextualMeaning,
      exampleSentence: draft.exampleSentence,
      sentenceTranslation: draft.sentenceTranslation,
      sourceApplicationName: addition.sourceApplicationName,
      encounteredAt: addition.createdAt
    )
  }

  private func backfillLegacyEncounterIfNeeded(_ record: LearningRecord) {
    guard record.encounters.isEmpty else {
      return
    }

    record.normalizedCanonicalForm = NormalizedCanonicalForm(record.canonicalForm).value
    record.lastEncounteredAt = record.createdAt
    record.encounters.append(
      LearningEncounterRecord(
        sourceText: record.sourceText,
        pronunciation: record.pronunciation,
        partOfSpeech: record.partOfSpeech,
        contextualMeaning: record.contextualMeaning,
        exampleSentence: record.exampleSentence,
        sentenceTranslation: record.sentenceTranslation,
        sourceApplicationName: record.sourceApplicationName,
        encounteredAt: record.createdAt
      ))
  }

  private func updateLatestSnapshot(
    of record: LearningRecord,
    from addition: LearningAddition
  ) {
    let draft = addition.draft
    record.sourceText = draft.sourceText
    record.pronunciation = draft.pronunciation
    record.partOfSpeech = draft.partOfSpeech
    record.contextualMeaning = draft.contextualMeaning
    record.exampleSentence = draft.exampleSentence
    record.sentenceTranslation = draft.sentenceTranslation
    record.sourceApplicationName = addition.sourceApplicationName
  }

  private func encounterItems(for record: LearningRecord) -> [LearningEncounter] {
    let persistedEncounters =
      if record.encounters.isEmpty {
        [
          LearningEncounter(
            id: record.id,
            sourceText: record.sourceText,
            pronunciation: record.pronunciation,
            partOfSpeech: record.partOfSpeech,
            contextualMeaning: record.contextualMeaning,
            exampleSentence: record.exampleSentence,
            sentenceTranslation: record.sentenceTranslation,
            sourceApplicationName: record.sourceApplicationName,
            encounteredAt: record.createdAt
          )
        ]
      } else {
        record.encounters.map { encounter in
          LearningEncounter(
            id: encounter.id,
            sourceText: encounter.sourceText,
            pronunciation: encounter.pronunciation,
            partOfSpeech: encounter.partOfSpeech,
            contextualMeaning: encounter.contextualMeaning,
            exampleSentence: encounter.exampleSentence,
            sentenceTranslation: encounter.sentenceTranslation,
            sourceApplicationName: encounter.sourceApplicationName,
            encounteredAt: encounter.encounteredAt
          )
        }
      }

    return persistedEncounters.sorted { $0.encounteredAt > $1.encounteredAt }
  }

  private func merge(
    _ sourceRecord: LearningRecord,
    into targetRecord: LearningRecord
  ) {
    backfillLegacyEncounterIfNeeded(sourceRecord)
    backfillLegacyEncounterIfNeeded(targetRecord)

    if sourceRecord.lastEncounteredAt > targetRecord.lastEncounteredAt {
      copyLatestSnapshot(from: sourceRecord, to: targetRecord)
    }

    let sourceEncounters = Array(sourceRecord.encounters)
    targetRecord.encounters.append(contentsOf: sourceEncounters)
    targetRecord.createdAt = min(targetRecord.createdAt, sourceRecord.createdAt)
    targetRecord.lastEncounteredAt = max(
      targetRecord.lastEncounteredAt,
      sourceRecord.lastEncounteredAt
    )
    targetRecord.nextReviewAt = earlierDate(
      targetRecord.nextReviewAt,
      sourceRecord.nextReviewAt
    )
    targetRecord.isPaused = targetRecord.isPaused && sourceRecord.isPaused
    context.delete(sourceRecord)
  }

  private func copyLatestSnapshot(
    from sourceRecord: LearningRecord,
    to targetRecord: LearningRecord
  ) {
    targetRecord.sourceText = sourceRecord.sourceText
    targetRecord.pronunciation = sourceRecord.pronunciation
    targetRecord.partOfSpeech = sourceRecord.partOfSpeech
    targetRecord.contextualMeaning = sourceRecord.contextualMeaning
    targetRecord.exampleSentence = sourceRecord.exampleSentence
    targetRecord.sentenceTranslation = sourceRecord.sentenceTranslation
    targetRecord.sourceApplicationName = sourceRecord.sourceApplicationName
  }

  private func earlierDate(_ first: Date?, _ second: Date?) -> Date? {
    switch (first, second) {
    case (.none, .none):
      nil
    case (.some(let date), .none), (.none, .some(let date)):
      date
    case (.some(let firstDate), .some(let secondDate)):
      min(firstDate, secondDate)
    }
  }
}

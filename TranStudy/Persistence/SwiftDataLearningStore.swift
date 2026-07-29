import Foundation
import SwiftData

enum LearningStoreError: Error {
  case emptyCanonicalForm
  case missingLearningItem
}

@MainActor
final class SwiftDataLearningStore: LearningStoring {
  private struct LearningIdentity: Hashable {
    let kind: LearningContentKind
    let value: String
  }

  private let context: ModelContext

  init(container: ModelContainer) {
    context = ModelContext(container)
  }

  func summary(at date: Date) async throws -> LearningSummary {
    let records = try consolidatedRecords().filter { $0.archivedAt == nil }
    let dueCount = records.count(where: {
      !$0.isPaused && ($0.nextReviewAt ?? .distantFuture) <= date
    })

    return LearningSummary(
      dueCount: dueCount,
      wordCount: records.count(where: { learningKind(for: $0) == .word }),
      sentenceCount: records.count(where: { learningKind(for: $0) == .sentence })
    )
  }

  func dueItems(at date: Date) async throws -> [LearningItem] {
    try await items()
      .filter {
        !$0.isPaused && ($0.nextReviewAt ?? .distantFuture) <= date
      }
      .sorted { first, second in
        let firstReviewDate = first.nextReviewAt ?? .distantFuture
        let secondReviewDate = second.nextReviewAt ?? .distantFuture
        if firstReviewDate != secondReviewDate {
          return firstReviewDate < secondReviewDate
        }
        return first.id.uuidString < second.id.uuidString
      }
  }

  func recordReview(
    itemID: UUID,
    rating: ReviewRating,
    reviewedAt: Date
  ) async throws -> LearningReviewResult {
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }

    let previousReviewAt = record.reviewEvents.map(\.reviewedAt).max()
    let schedule = nextSchedule(
      rating: rating,
      currentIntervalDays: max(1, record.reviewIntervalDays),
      currentEase: record.reviewEase
    )
    let nextReviewAt = date(
      byAddingDays: Int(schedule.intervalDays),
      to: reviewedAt
    )
    record.nextReviewAt = nextReviewAt
    record.reviewIntervalDays = schedule.intervalDays
    record.reviewEase = schedule.ease
    record.reviewCount += 1
    if rating == .forgot {
      record.lapseCount += 1
    }
    record.reviewEvents.append(
      ReviewEventRecord(
        rating: rating,
        reviewedAt: reviewedAt,
        previousReviewAt: previousReviewAt,
        nextReviewAt: nextReviewAt,
        intervalDays: schedule.intervalDays
      ))
    try context.save()

    return LearningReviewResult(
      itemID: itemID,
      rating: rating,
      reviewedAt: reviewedAt,
      nextReviewAt: nextReviewAt,
      intervalDays: schedule.intervalDays
    )
  }

  func reviewHistory(itemID: UUID) async throws -> [LearningReviewEvent] {
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }

    return record.reviewEvents
      .compactMap { event in
        guard let rating = ReviewRating(rawValue: event.ratingRawValue) else {
          return nil
        }
        return LearningReviewEvent(
          id: event.id,
          rating: rating,
          reviewedAt: event.reviewedAt,
          previousReviewAt: event.previousReviewAt,
          nextReviewAt: event.nextReviewAt,
          intervalDays: event.intervalDays
        )
      }
      .sorted { $0.reviewedAt < $1.reviewedAt }
  }

  func add(_ addition: LearningAddition) async throws {
    let draft = addition.draft
    let normalizedForm = normalizedIdentity(for: addition).value
    guard !normalizedForm.isEmpty else {
      throw LearningStoreError.emptyCanonicalForm
    }
    let records = try consolidatedRecords()

    if let existingRecord = records.first(where: {
      normalizedIdentity(for: $0)
        == LearningIdentity(kind: addition.kind, value: normalizedForm)
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
      kind: addition.kind,
      createdAt: addition.createdAt,
      sourceText: displaySourceText(for: addition),
      canonicalForm:
        addition.kind == .sentence
        ? displaySourceText(for: addition)
        : draft.canonicalForm.trimmingCharacters(in: .whitespacesAndNewlines),
      pronunciation: draft.pronunciation,
      partOfSpeech: draft.partOfSpeech,
      contextualMeaning: draft.contextualMeaning,
      exampleSentence: draft.exampleSentence,
      sentenceTranslation: draft.sentenceTranslation,
      sourceApplicationName: addition.sourceApplicationName,
      nextReviewAt: addition.nextReviewAt ?? addition.createdAt,
      isPaused: addition.isPaused
    )
    record.encounters.append(makeEncounter(from: addition))

    context.insert(record)
    try context.save()
  }

  func mergeSummary(for addition: LearningAddition) async throws -> LearningMergeSummary? {
    guard addition.kind == .word else {
      return nil
    }
    let normalizedForm = normalizedIdentity(for: addition).value
    let records = try consolidatedRecords()
    guard
      let existingRecord = records.first(where: {
        learningKind(for: $0) == .word
          && normalizedCanonicalForm(for: $0) == normalizedForm
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
    let records = try consolidatedRecords()
    let result = applyCanonicalForm(
      itemID: itemID,
      canonicalForm: canonicalForm,
      confirmMerge: confirmMerge,
      records: records
    )
    if case .requiresConfirmation = result {
      return result
    }
    try saveOrRollback()
    return result
  }

  func updateItem(
    itemID: UUID,
    canonicalForm: String,
    details: LearningItemDetailsUpdate
  ) async throws -> LearningCanonicalUpdateResult {
    let trimmedCanonicalForm = canonicalForm.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !NormalizedCanonicalForm(trimmedCanonicalForm).value.isEmpty else {
      throw LearningStoreError.emptyCanonicalForm
    }
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }

    applyDetails(details, to: record)
    let result = applyCanonicalForm(
      itemID: itemID,
      canonicalForm: canonicalForm,
      confirmMerge: false,
      records: records
    )
    try saveOrRollback()
    return result
  }

  private func applyCanonicalForm(
    itemID: UUID,
    canonicalForm: String,
    confirmMerge: Bool,
    records: [LearningRecord]
  ) -> LearningCanonicalUpdateResult {
    let trimmedCanonicalForm = canonicalForm.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalizedForm = NormalizedCanonicalForm(trimmedCanonicalForm).value
    guard !normalizedForm.isEmpty else {
      return .updated
    }

    guard let sourceRecord = records.first(where: { $0.id == itemID }) else {
      return .updated
    }
    guard learningKind(for: sourceRecord) == .word else {
      return .updated
    }

    if normalizedCanonicalForm(for: sourceRecord) == normalizedForm {
      sourceRecord.canonicalForm = trimmedCanonicalForm
      sourceRecord.normalizedCanonicalForm = normalizedForm
      return .updated
    }

    guard
      let targetRecord = records.first(where: {
        $0.id != itemID && learningKind(for: $0) == .word
          && normalizedCanonicalForm(for: $0) == normalizedForm
      })
    else {
      sourceRecord.canonicalForm = trimmedCanonicalForm
      sourceRecord.normalizedCanonicalForm = normalizedForm
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

    merge(sourceRecord, into: targetRecord, preferSourceSnapshot: true)
    return .merged
  }

  func updateDetails(
    itemID: UUID,
    details: LearningItemDetailsUpdate
  ) async throws {
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }

    applyDetails(details, to: record)
    try saveOrRollback()
  }

  private func applyDetails(
    _ details: LearningItemDetailsUpdate,
    to record: LearningRecord
  ) {
    backfillLegacyEncounterIfNeeded(record)
    record.pronunciation = details.pronunciation.trimmingCharacters(in: .whitespacesAndNewlines)
    record.partOfSpeech = details.partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
    record.contextualMeaning =
      details.contextualMeaning.trimmingCharacters(in: .whitespacesAndNewlines)
    record.exampleSentence =
      TranslationTextNormalizer.collapseWhitespace(in: details.exampleSentence)
    record.sentenceTranslation =
      TranslationTextNormalizer.collapseWhitespace(in: details.sentenceTranslation)
    record.userNote = details.userNote.trimmingCharacters(in: .whitespacesAndNewlines)

    let existingExamples = Dictionary(
      uniqueKeysWithValues: record.customExamples.map { ($0.id, $0) }
    )
    let updatedExamples: [LearningCustomExampleRecord] =
      details.customExamples.enumerated().compactMap { index, example in
        let englishText = TranslationTextNormalizer.collapseWhitespace(in: example.englishText)
        guard !englishText.isEmpty else {
          return nil
        }
        let persistedExample =
          existingExamples[example.id]
          ?? LearningCustomExampleRecord(
            id: example.id,
            englishText: englishText,
            chineseTranslation: "",
            sortOrder: index
          )
        persistedExample.englishText = englishText
        persistedExample.chineseTranslation =
          TranslationTextNormalizer.collapseWhitespace(in: example.chineseTranslation)
        persistedExample.sortOrder = index
        return persistedExample
      }
    let updatedIDs = Set(updatedExamples.map(\.id))
    for example in record.customExamples where !updatedIDs.contains(example.id) {
      context.delete(example)
    }
    record.customExamples = updatedExamples
  }

  private func saveOrRollback() throws {
    do {
      try context.save()
    } catch {
      context.rollback()
      throw error
    }
  }

  func items() async throws -> [LearningItem] {
    try learningItems(archived: false)
  }

  func archivedItems() async throws -> [LearningItem] {
    try learningItems(archived: true)
  }

  func setArchived(itemIDs: [UUID], archivedAt: Date?) async throws {
    let selectedIDs = Set(itemIDs)
    guard !selectedIDs.isEmpty else {
      return
    }
    let records = try consolidatedRecords()
    for record in records where selectedIDs.contains(record.id) {
      record.archivedAt = archivedAt
    }
    try context.save()
  }

  func setNextReviewDate(itemID: UUID, nextReviewAt: Date) async throws {
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }
    record.nextReviewAt = nextReviewAt
    try saveOrRollback()
  }

  func setReviewPaused(itemID: UUID, isPaused: Bool) async throws {
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }
    record.isPaused = isPaused
    try saveOrRollback()
  }

  func resetReviewProgress(itemID: UUID, resetAt: Date) async throws {
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }
    for event in record.reviewEvents {
      context.delete(event)
    }
    record.reviewEvents = []
    record.nextReviewAt = resetAt
    record.reviewIntervalDays = 1
    record.reviewEase = 2.5
    record.reviewCount = 0
    record.lapseCount = 0
    try saveOrRollback()
  }

  private func learningItems(archived: Bool) throws -> [LearningItem] {
    try consolidatedRecords()
      .filter { ($0.archivedAt != nil) == archived }
      .sorted { effectiveLastEncounteredAt(for: $0) > effectiveLastEncounteredAt(for: $1) }
      .map { record in
        let encounters = encounterItems(for: record)

        return LearningItem(
          id: record.id,
          kind: learningKind(for: record),
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
          userNote: record.userNote,
          customExamples: record.customExamples
            .sorted {
              if $0.sortOrder != $1.sortOrder {
                return $0.sortOrder < $1.sortOrder
              }
              return $0.id.uuidString < $1.id.uuidString
            }
            .map {
              LearningCustomExample(
                id: $0.id,
                englishText: $0.englishText,
                chineseTranslation: $0.chineseTranslation
              )
            },
          nextReviewAt: record.nextReviewAt,
          isPaused: record.isPaused,
          archivedAt: record.archivedAt
        )
      }
  }

  private func consolidatedRecords() throws -> [LearningRecord] {
    var descriptor = FetchDescriptor<LearningRecord>()
    descriptor.includePendingChanges = true
    let records = try context.fetch(descriptor)
    let groupedRecords = Dictionary(grouping: records, by: normalizedIdentity(for:))
    var didChange = false

    for record in records where record.nextReviewAt == nil {
      record.nextReviewAt = record.createdAt
      didChange = true
    }

    for (identity, duplicates) in groupedRecords
    where !identity.value.isEmpty && duplicates.count > 1 {
      let orderedDuplicates = duplicates.sorted { $0.createdAt < $1.createdAt }
      guard let targetRecord = orderedDuplicates.first else {
        continue
      }

      for sourceRecord in orderedDuplicates.dropFirst() {
        merge(sourceRecord, into: targetRecord)
        didChange = true
      }
    }

    if didChange {
      try context.save()
      return try context.fetch(descriptor)
    }
    return records
  }

  private func effectiveLastEncounteredAt(for record: LearningRecord) -> Date {
    record.encounters.map(\.encounteredAt).max() ?? record.createdAt
  }

  private func date(byAddingDays days: Int, to date: Date) -> Date {
    Calendar.autoupdatingCurrent.date(byAdding: .day, value: days, to: date)
      ?? date.addingTimeInterval(Double(days) * 86_400)
  }

  private func nextSchedule(
    rating: ReviewRating,
    currentIntervalDays: Double,
    currentEase: Double
  ) -> (intervalDays: Double, ease: Double) {
    switch rating {
    case .forgot:
      return (1, max(1.3, currentEase - 0.2))
    case .hard:
      return (max(2, ceil(currentIntervalDays * 1.2)), max(1.3, currentEase - 0.15))
    case .remembered:
      return (max(3, ceil(currentIntervalDays * currentEase)), currentEase)
    case .easy:
      let nextEase = currentEase + 0.15
      return (max(5, ceil(currentIntervalDays * (nextEase + 1))), nextEase)
    }
  }

  private func normalizedCanonicalForm(for record: LearningRecord) -> String {
    if !record.normalizedCanonicalForm.isEmpty {
      return record.normalizedCanonicalForm
    }
    return NormalizedCanonicalForm(record.canonicalForm).value
  }

  private func normalizedIdentity(for addition: LearningAddition) -> LearningIdentity {
    LearningIdentity(
      kind: addition.kind,
      value:
        addition.kind == .sentence
        ? TranslationTextNormalizer.collapseWhitespace(in: addition.draft.sourceText)
        : NormalizedCanonicalForm(addition.draft.canonicalForm).value
    )
  }

  private func normalizedIdentity(for record: LearningRecord) -> LearningIdentity {
    let kind = learningKind(for: record)
    return LearningIdentity(
      kind: kind,
      value:
        kind == .sentence
        ? TranslationTextNormalizer.collapseWhitespace(in: record.sourceText)
        : normalizedCanonicalForm(for: record)
    )
  }

  private func learningKind(for record: LearningRecord) -> LearningContentKind {
    LearningContentKind(rawValue: record.kindRawValue) ?? .word
  }

  private func displaySourceText(for addition: LearningAddition) -> String {
    addition.kind == .sentence
      ? TranslationTextNormalizer.collapseWhitespace(in: addition.draft.sourceText)
      : addition.draft.sourceText
  }

  private func makeEncounter(from addition: LearningAddition) -> LearningEncounterRecord {
    let draft = addition.draft
    return LearningEncounterRecord(
      sourceText: displaySourceText(for: addition),
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

    record.normalizedCanonicalForm = normalizedIdentity(for: record).value
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
    record.sourceText = displaySourceText(for: addition)
    if addition.kind == .sentence {
      record.canonicalForm = displaySourceText(for: addition)
    }
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
    into targetRecord: LearningRecord,
    preferSourceSnapshot: Bool = false
  ) {
    backfillLegacyEncounterIfNeeded(sourceRecord)
    backfillLegacyEncounterIfNeeded(targetRecord)

    if preferSourceSnapshot
      || sourceRecord.lastEncounteredAt > targetRecord.lastEncounteredAt
    {
      copyLatestSnapshot(from: sourceRecord, to: targetRecord)
    }

    let sourceEncounters = Array(sourceRecord.encounters)
    targetRecord.encounters.append(contentsOf: sourceEncounters)
    let useSourceSchedule = isEarlier(
      sourceRecord.nextReviewAt,
      than: targetRecord.nextReviewAt
    )
    if useSourceSchedule {
      targetRecord.reviewIntervalDays = sourceRecord.reviewIntervalDays
      targetRecord.reviewEase = sourceRecord.reviewEase
    }
    targetRecord.reviewCount += sourceRecord.reviewCount
    targetRecord.lapseCount += sourceRecord.lapseCount
    let sourceReviewEvents = Array(sourceRecord.reviewEvents)
    targetRecord.reviewEvents.append(contentsOf: sourceReviewEvents)
    let sourceCustomExamples = Array(sourceRecord.customExamples)
    targetRecord.customExamples.append(contentsOf: sourceCustomExamples)
    for (index, example) in targetRecord.customExamples.enumerated() {
      example.sortOrder = index
    }
    targetRecord.userNote = mergedUserNote(
      targetRecord.userNote,
      sourceRecord.userNote
    )
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
    targetRecord.archivedAt = earlierArchiveState(
      targetRecord.archivedAt,
      sourceRecord.archivedAt
    )
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

  private func isEarlier(_ candidate: Date?, than current: Date?) -> Bool {
    switch (candidate, current) {
    case (.some(let candidateDate), .some(let currentDate)):
      candidateDate < currentDate
    case (.some, .none):
      true
    case (.none, _):
      false
    }
  }

  private func earlierArchiveState(_ first: Date?, _ second: Date?) -> Date? {
    guard let first, let second else {
      return nil
    }
    return min(first, second)
  }

  private func mergedUserNote(_ first: String, _ second: String) -> String {
    let notes = [first, second]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    var uniqueNotes: [String] = []
    for note in notes where !uniqueNotes.contains(note) {
      uniqueNotes.append(note)
    }
    return uniqueNotes.joined(separator: "\n\n")
  }
}

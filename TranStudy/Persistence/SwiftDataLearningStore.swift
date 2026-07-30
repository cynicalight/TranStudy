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

  private struct EncounterSignature: Hashable {
    let sourceText: String
    let pronunciation: String
    let partOfSpeech: String
    let contextualMeaning: String
    let exampleSentence: String
    let sentenceTranslation: String
    let sourceApplicationName: String
    let encounteredAt: Date
  }

  private struct ExampleSignature: Hashable {
    let englishText: String
    let chineseTranslation: String
  }

  private let context: ModelContext
  private let calendar: Calendar

  init(
    container: ModelContainer,
    calendar: Calendar = .autoupdatingCurrent
  ) {
    context = ModelContext(container)
    self.calendar = calendar
  }

  func summary(at date: Date) async throws -> LearningSummary {
    let records = try consolidatedRecords().filter {
      $0.deletionScheduledAt == nil
    }
    let activeRecords = records.filter { $0.archivedAt == nil }
    let dueCount = activeRecords.count(where: {
      !$0.isPaused && ($0.nextReviewAt ?? .distantFuture) <= date
    })
    let reviewDays = records.flatMap(\.reviewEvents).map {
      calendar.startOfDay(for: $0.reviewedAt)
    }
    let today = calendar.startOfDay(for: date)

    return LearningSummary(
      dueCount: dueCount,
      reviewedTodayCount: reviewDays.count(where: { $0 == today }),
      streakDayCount: streakDayCount(reviewDays: Set(reviewDays), today: today),
      wordCount: activeRecords.count(where: { learningKind(for: $0) == .word }),
      sentenceCount: activeRecords.count(where: { learningKind(for: $0) == .sentence })
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

  func scheduleDeletion(itemID: UUID, deleteAt: Date) async throws {
    let record = try learningRecord(itemID: itemID)
    record.deletionScheduledAt = deleteAt
    try saveOrRollback()
  }

  func cancelDeletion(itemID: UUID) async throws {
    let record = try learningRecord(itemID: itemID)
    record.deletionScheduledAt = nil
    try saveOrRollback()
  }

  func pendingDeletion() async throws -> PendingLearningDeletion? {
    let scheduledRecords = try consolidatedRecords()
      .filter { $0.deletionScheduledAt != nil }
      .sorted {
        ($0.deletionScheduledAt ?? .distantFuture)
          < ($1.deletionScheduledAt ?? .distantFuture)
      }
    guard
      let record = scheduledRecords.first,
      let deleteAt = record.deletionScheduledAt
    else {
      return nil
    }
    return PendingLearningDeletion(
      item: learningItem(from: record),
      deleteAt: deleteAt
    )
  }

  func deleteExpiredItems(at date: Date) async throws {
    let expiredRecords = try consolidatedRecords().filter {
      ($0.deletionScheduledAt ?? .distantFuture) <= date
    }
    guard !expiredRecords.isEmpty else {
      return
    }
    for record in expiredRecords {
      context.delete(record)
    }
    try saveOrRollback()
  }

  func delete(itemID: UUID) async throws {
    let record = try learningRecord(itemID: itemID)
    context.delete(record)
    try saveOrRollback()
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

  func exportArchive(exportedAt: Date) async throws -> LearningDataArchive {
    let items = try consolidatedRecords()
      .sorted { $0.id.uuidString < $1.id.uuidString }
      .map { record in
        LearningDataArchive.Item(
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
          lastEncounteredAt: effectiveLastEncounteredAt(for: record),
          userNote: record.userNote,
          nextReviewAt: record.nextReviewAt,
          isPaused: record.isPaused,
          archivedAt: record.archivedAt,
          reviewIntervalDays: record.reviewIntervalDays,
          reviewEase: record.reviewEase,
          reviewCount: record.reviewCount,
          lapseCount: record.lapseCount,
          encounters: encounterItems(for: record).map {
            LearningDataArchive.Encounter(
              id: $0.id,
              sourceText: $0.sourceText,
              pronunciation: $0.pronunciation,
              partOfSpeech: $0.partOfSpeech,
              contextualMeaning: $0.contextualMeaning,
              exampleSentence: $0.exampleSentence,
              sentenceTranslation: $0.sentenceTranslation,
              sourceApplicationName: $0.sourceApplicationName,
              encounteredAt: $0.encounteredAt
            )
          },
          customExamples: record.customExamples
            .sorted { $0.sortOrder < $1.sortOrder }
            .map {
              LearningDataArchive.CustomExample(
                id: $0.id,
                englishText: $0.englishText,
                chineseTranslation: $0.chineseTranslation
              )
            },
          reviewEvents: record.reviewEvents.compactMap { event in
            guard let rating = ReviewRating(rawValue: event.ratingRawValue) else {
              return nil
            }
            return LearningDataArchive.ReviewEvent(
              id: event.id,
              rating: rating,
              reviewedAt: event.reviewedAt,
              previousReviewAt: event.previousReviewAt,
              nextReviewAt: event.nextReviewAt,
              intervalDays: event.intervalDays
            )
          }
        )
      }
    return LearningDataArchive(exportedAt: exportedAt, items: items)
  }

  func importArchive(_ archive: LearningDataArchive) async throws -> LearningDataImportSummary {
    guard archive.formatVersion == LearningDataArchive.currentFormatVersion else {
      throw LearningDataArchiveError.unsupportedFormatVersion(archive.formatVersion)
    }
    var records = try consolidatedRecords()
    var importedItemCount = 0
    var mergedItemCount = 0

    for item in archive.items {
      let identity = archiveIdentity(for: item)
      let target =
        records.first(where: { $0.id == item.id })
        ?? records.first(where: { normalizedIdentity(for: $0) == identity })

      if let target {
        mergeImportedItem(item, into: target)
        mergedItemCount += 1
      } else {
        let record = makeRecord(from: item)
        context.insert(record)
        records.append(record)
        importedItemCount += 1
      }
    }
    try saveOrRollback()
    return LearningDataImportSummary(
      importedItemCount: importedItemCount,
      mergedItemCount: mergedItemCount
    )
  }

  func deleteAllLearningData() async throws {
    let records = try context.fetch(FetchDescriptor<LearningRecord>())
    for record in records {
      context.delete(record)
    }
    try saveOrRollback()
  }

  private func learningItems(archived: Bool) throws -> [LearningItem] {
    try consolidatedRecords()
      .filter {
        ($0.archivedAt != nil) == archived && $0.deletionScheduledAt == nil
      }
      .sorted { effectiveLastEncounteredAt(for: $0) > effectiveLastEncounteredAt(for: $1) }
      .map(learningItem(from:))
  }

  private func archiveIdentity(for item: LearningDataArchive.Item) -> LearningIdentity {
    LearningIdentity(
      kind: item.kind,
      value:
        item.kind == .sentence
        ? TranslationTextNormalizer.collapseWhitespace(in: item.sourceText)
        : NormalizedCanonicalForm(item.canonicalForm).value
    )
  }

  private func makeRecord(from item: LearningDataArchive.Item) -> LearningRecord {
    let record = LearningRecord(
      id: item.id,
      kind: item.kind,
      createdAt: item.createdAt,
      sourceText: item.sourceText,
      canonicalForm: item.canonicalForm,
      pronunciation: item.pronunciation,
      partOfSpeech: item.partOfSpeech,
      contextualMeaning: item.contextualMeaning,
      exampleSentence: item.exampleSentence,
      sentenceTranslation: item.sentenceTranslation,
      sourceApplicationName: item.sourceApplicationName,
      nextReviewAt: item.nextReviewAt,
      isPaused: item.isPaused
    )
    record.lastEncounteredAt = item.lastEncounteredAt
    record.userNote = item.userNote
    record.archivedAt = item.archivedAt
    record.reviewIntervalDays = item.reviewIntervalDays
    record.reviewEase = item.reviewEase
    record.reviewCount = item.reviewCount
    record.lapseCount = item.lapseCount
    record.encounters = uniqueEncounters(item.encounters).map(makeEncounter(from:))
    record.customExamples = uniqueExamples(item.customExamples).enumerated().map {
      index, example in
      LearningCustomExampleRecord(
        id: example.id,
        englishText: example.englishText,
        chineseTranslation: example.chineseTranslation,
        sortOrder: index
      )
    }
    var reviewEventIDs: Set<UUID> = []
    record.reviewEvents = item.reviewEvents.compactMap { event in
      guard reviewEventIDs.insert(event.id).inserted else {
        return nil
      }
      return makeReviewEvent(from: event)
    }
    return record
  }

  private func uniqueEncounters(
    _ encounters: [LearningDataArchive.Encounter]
  ) -> [LearningDataArchive.Encounter] {
    var ids: Set<UUID> = []
    var signatures: Set<EncounterSignature> = []
    return encounters.filter { encounter in
      ids.insert(encounter.id).inserted
        && signatures.insert(encounterSignature(encounter)).inserted
    }
  }

  private func uniqueExamples(
    _ examples: [LearningDataArchive.CustomExample]
  ) -> [LearningDataArchive.CustomExample] {
    var ids: Set<UUID> = []
    var signatures: Set<ExampleSignature> = []
    return examples.filter { example in
      ids.insert(example.id).inserted
        && signatures.insert(exampleSignature(example)).inserted
    }
  }

  private func mergeImportedItem(
    _ item: LearningDataArchive.Item,
    into record: LearningRecord
  ) {
    let useImportedSnapshot = item.lastEncounteredAt > effectiveLastEncounteredAt(for: record)
    if useImportedSnapshot {
      record.sourceText = item.sourceText
      record.canonicalForm = item.canonicalForm
      record.pronunciation = item.pronunciation
      record.partOfSpeech = item.partOfSpeech
      record.contextualMeaning = item.contextualMeaning
      record.exampleSentence = item.exampleSentence
      record.sentenceTranslation = item.sentenceTranslation
      record.sourceApplicationName = item.sourceApplicationName
      record.normalizedCanonicalForm = archiveIdentity(for: item).value
    }
    record.createdAt = min(record.createdAt, item.createdAt)
    record.lastEncounteredAt = max(effectiveLastEncounteredAt(for: record), item.lastEncounteredAt)
    let useImportedSchedule = isEarlier(item.nextReviewAt, than: record.nextReviewAt)
    if useImportedSchedule {
      record.reviewIntervalDays = item.reviewIntervalDays
      record.reviewEase = item.reviewEase
    }
    record.nextReviewAt = earlierDate(record.nextReviewAt, item.nextReviewAt)
    record.isPaused = record.isPaused && item.isPaused
    record.archivedAt = earlierArchiveState(record.archivedAt, item.archivedAt)
    record.userNote = mergedUserNote(record.userNote, item.userNote)

    var encounterIDs = Set(record.encounters.map(\.id))
    var encounterSignatures = Set(record.encounters.map(encounterSignature))
    for encounter in item.encounters {
      let signature = encounterSignature(encounter)
      guard !encounterIDs.contains(encounter.id), !encounterSignatures.contains(signature) else {
        continue
      }
      record.encounters.append(makeEncounter(from: encounter))
      encounterIDs.insert(encounter.id)
      encounterSignatures.insert(signature)
    }

    var exampleIDs = Set(record.customExamples.map(\.id))
    var exampleSignatures = Set(record.customExamples.map(exampleSignature))
    for example in item.customExamples {
      let signature = exampleSignature(example)
      guard !exampleIDs.contains(example.id), !exampleSignatures.contains(signature) else {
        continue
      }
      record.customExamples.append(
        LearningCustomExampleRecord(
          id: example.id,
          englishText: example.englishText,
          chineseTranslation: example.chineseTranslation,
          sortOrder: record.customExamples.count
        )
      )
      exampleIDs.insert(example.id)
      exampleSignatures.insert(signature)
    }

    var eventIDs = Set(record.reviewEvents.map(\.id))
    for event in item.reviewEvents where !eventIDs.contains(event.id) {
      record.reviewEvents.append(makeReviewEvent(from: event))
      eventIDs.insert(event.id)
    }
    record.reviewCount = max(record.reviewCount, item.reviewCount, record.reviewEvents.count)
    record.lapseCount = max(
      record.lapseCount,
      item.lapseCount,
      record.reviewEvents.count(where: { $0.ratingRawValue == ReviewRating.forgot.rawValue })
    )
  }

  private func makeEncounter(
    from encounter: LearningDataArchive.Encounter
  ) -> LearningEncounterRecord {
    LearningEncounterRecord(
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

  private func makeReviewEvent(
    from event: LearningDataArchive.ReviewEvent
  ) -> ReviewEventRecord {
    ReviewEventRecord(
      id: event.id,
      rating: event.rating,
      reviewedAt: event.reviewedAt,
      previousReviewAt: event.previousReviewAt,
      nextReviewAt: event.nextReviewAt,
      intervalDays: event.intervalDays
    )
  }

  private func encounterSignature(_ encounter: LearningEncounterRecord) -> EncounterSignature {
    EncounterSignature(
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

  private func encounterSignature(
    _ encounter: LearningDataArchive.Encounter
  ) -> EncounterSignature {
    EncounterSignature(
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

  private func exampleSignature(_ example: LearningCustomExampleRecord) -> ExampleSignature {
    ExampleSignature(
      englishText: TranslationTextNormalizer.collapseWhitespace(in: example.englishText),
      chineseTranslation:
        TranslationTextNormalizer.collapseWhitespace(in: example.chineseTranslation)
    )
  }

  private func exampleSignature(
    _ example: LearningDataArchive.CustomExample
  ) -> ExampleSignature {
    ExampleSignature(
      englishText: TranslationTextNormalizer.collapseWhitespace(in: example.englishText),
      chineseTranslation:
        TranslationTextNormalizer.collapseWhitespace(in: example.chineseTranslation)
    )
  }

  private func learningRecord(itemID: UUID) throws -> LearningRecord {
    let records = try consolidatedRecords()
    guard let record = records.first(where: { $0.id == itemID }) else {
      throw LearningStoreError.missingLearningItem
    }
    return record
  }

  private func learningItem(from record: LearningRecord) -> LearningItem {
    LearningItem(
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
      encounters: encounterItems(for: record),
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

  private func streakDayCount(reviewDays: Set<Date>, today: Date) -> Int {
    var cursor = today
    if !reviewDays.contains(cursor) {
      cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
    }
    var count = 0
    while reviewDays.contains(cursor) {
      count += 1
      guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else {
        break
      }
      cursor = previousDay
    }
    return count
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

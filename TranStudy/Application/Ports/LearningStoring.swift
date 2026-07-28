import Foundation

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

struct LearningAddition: Equatable, Sendable {
  let draft: TranslationDraft
  let sourceApplicationName: String
  let createdAt: Date
  let nextReviewAt: Date?
  let isPaused: Bool

  init(
    draft: TranslationDraft,
    sourceApplicationName: String,
    createdAt: Date,
    nextReviewAt: Date? = nil,
    isPaused: Bool = false
  ) {
    self.draft = draft
    self.sourceApplicationName = sourceApplicationName
    self.createdAt = createdAt
    self.nextReviewAt = nextReviewAt
    self.isPaused = isPaused
  }
}

struct LearningEncounter: Equatable, Identifiable, Sendable {
  let id: UUID
  let sourceText: String
  let pronunciation: String
  let partOfSpeech: String
  let contextualMeaning: String
  let exampleSentence: String
  let sentenceTranslation: String
  let sourceApplicationName: String
  let encounteredAt: Date
}

struct LearningMergeSummary: Equatable, Sendable {
  let existingItemID: UUID
  let canonicalForm: String
  let existingEncounterCount: Int
  let incomingSourceText: String
}

enum LearningCanonicalUpdateResult: Equatable, Sendable {
  case updated
  case requiresConfirmation(LearningMergeSummary)
  case merged
}

struct LearningItem: Equatable, Identifiable, Sendable {
  let id: UUID
  let sourceText: String
  let canonicalForm: String
  let pronunciation: String
  let partOfSpeech: String
  let contextualMeaning: String
  let exampleSentence: String
  let sentenceTranslation: String
  let sourceApplicationName: String
  let createdAt: Date
  let encounters: [LearningEncounter]
  let nextReviewAt: Date?
  let isPaused: Bool

  init(
    id: UUID,
    sourceText: String,
    canonicalForm: String,
    pronunciation: String,
    partOfSpeech: String,
    contextualMeaning: String,
    exampleSentence: String,
    sentenceTranslation: String,
    sourceApplicationName: String,
    createdAt: Date,
    encounters: [LearningEncounter] = [],
    nextReviewAt: Date? = nil,
    isPaused: Bool = false
  ) {
    self.id = id
    self.sourceText = sourceText
    self.canonicalForm = canonicalForm
    self.pronunciation = pronunciation
    self.partOfSpeech = partOfSpeech
    self.contextualMeaning = contextualMeaning
    self.exampleSentence = exampleSentence
    self.sentenceTranslation = sentenceTranslation
    self.sourceApplicationName = sourceApplicationName
    self.createdAt = createdAt
    self.encounters = encounters
    self.nextReviewAt = nextReviewAt
    self.isPaused = isPaused
  }
}

@MainActor
protocol LearningStoring {
  func summary() async throws -> LearningSummary
  func add(_ addition: LearningAddition) async throws
  func mergeSummary(for addition: LearningAddition) async throws -> LearningMergeSummary?
  func updateCanonicalForm(
    itemID: UUID,
    canonicalForm: String,
    confirmMerge: Bool
  ) async throws -> LearningCanonicalUpdateResult
  func items() async throws -> [LearningItem]
}

extension LearningStoring {
  func mergeSummary(for addition: LearningAddition) async throws -> LearningMergeSummary? {
    nil
  }

  func updateCanonicalForm(
    itemID: UUID,
    canonicalForm: String,
    confirmMerge: Bool
  ) async throws -> LearningCanonicalUpdateResult {
    .updated
  }
}

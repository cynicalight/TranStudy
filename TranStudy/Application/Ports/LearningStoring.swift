import Foundation

enum LearningContentKind: String, Codable, Equatable, Hashable, Sendable {
  case word
  case sentence
}

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
  let kind: LearningContentKind
  let draft: TranslationDraft
  let sourceApplicationName: String
  let createdAt: Date
  let nextReviewAt: Date?
  let isPaused: Bool

  init(
    kind: LearningContentKind = .word,
    draft: TranslationDraft,
    sourceApplicationName: String,
    createdAt: Date,
    nextReviewAt: Date? = nil,
    isPaused: Bool = false
  ) {
    self.kind = kind
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

enum ReviewRating: String, CaseIterable, Equatable, Hashable, Sendable {
  case forgot
  case hard
  case remembered
  case easy
}

struct LearningReviewResult: Equatable, Sendable {
  let itemID: UUID
  let rating: ReviewRating
  let reviewedAt: Date
  let nextReviewAt: Date
  let intervalDays: Double
}

struct LearningReviewEvent: Equatable, Identifiable, Sendable {
  let id: UUID
  let rating: ReviewRating
  let reviewedAt: Date
  let previousReviewAt: Date?
  let nextReviewAt: Date
  let intervalDays: Double
}

struct LearningItem: Equatable, Identifiable, Sendable {
  let id: UUID
  let kind: LearningContentKind
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
    kind: LearningContentKind = .word,
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
    self.kind = kind
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
  func summary(at date: Date) async throws -> LearningSummary
  func dueItems(at date: Date) async throws -> [LearningItem]
  func recordReview(
    itemID: UUID,
    rating: ReviewRating,
    reviewedAt: Date
  ) async throws -> LearningReviewResult
  func reviewHistory(itemID: UUID) async throws -> [LearningReviewEvent]
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
  func reviewHistory(itemID: UUID) async throws -> [LearningReviewEvent] {
    []
  }

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

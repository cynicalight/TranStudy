import Foundation
import SwiftData

@Model
final class LearningRecord {
  @Attribute(.unique) var id: UUID
  var createdAt: Date
  var sourceText: String = ""
  var canonicalForm: String = ""
  var pronunciation: String = ""
  var partOfSpeech: String = ""
  var contextualMeaning: String = ""
  var exampleSentence: String = ""
  var sentenceTranslation: String = ""
  var sourceApplicationName: String = ""
  var normalizedCanonicalForm: String = ""
  var lastEncounteredAt: Date = Date()
  var nextReviewAt: Date?
  var isPaused: Bool = false
  var reviewIntervalDays: Double = 1
  var reviewEase: Double = 2.5
  var reviewCount: Int = 0
  var lapseCount: Int = 0
  @Relationship(deleteRule: .cascade, inverse: \LearningEncounterRecord.learningRecord)
  var encounters: [LearningEncounterRecord] = []
  @Relationship(deleteRule: .cascade, inverse: \ReviewEventRecord.learningRecord)
  var reviewEvents: [ReviewEventRecord] = []

  init(
    id: UUID = UUID(),
    createdAt: Date = Date(),
    sourceText: String,
    canonicalForm: String,
    pronunciation: String,
    partOfSpeech: String,
    contextualMeaning: String,
    exampleSentence: String,
    sentenceTranslation: String,
    sourceApplicationName: String,
    nextReviewAt: Date? = nil,
    isPaused: Bool = false
  ) {
    self.id = id
    self.createdAt = createdAt
    self.sourceText = sourceText
    self.canonicalForm = canonicalForm
    self.pronunciation = pronunciation
    self.partOfSpeech = partOfSpeech
    self.contextualMeaning = contextualMeaning
    self.exampleSentence = exampleSentence
    self.sentenceTranslation = sentenceTranslation
    self.sourceApplicationName = sourceApplicationName
    normalizedCanonicalForm = NormalizedCanonicalForm(canonicalForm).value
    lastEncounteredAt = createdAt
    self.nextReviewAt = nextReviewAt
    self.isPaused = isPaused
  }
}

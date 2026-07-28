import Foundation
import SwiftData

@Model
final class LearningEncounterRecord {
  @Attribute(.unique) var id: UUID
  var sourceText: String = ""
  var pronunciation: String = ""
  var partOfSpeech: String = ""
  var contextualMeaning: String = ""
  var exampleSentence: String = ""
  var sentenceTranslation: String = ""
  var sourceApplicationName: String = ""
  var encounteredAt: Date = Date()
  var learningRecord: LearningRecord?

  init(
    id: UUID = UUID(),
    sourceText: String,
    pronunciation: String,
    partOfSpeech: String,
    contextualMeaning: String,
    exampleSentence: String,
    sentenceTranslation: String,
    sourceApplicationName: String,
    encounteredAt: Date
  ) {
    self.id = id
    self.sourceText = sourceText
    self.pronunciation = pronunciation
    self.partOfSpeech = partOfSpeech
    self.contextualMeaning = contextualMeaning
    self.exampleSentence = exampleSentence
    self.sentenceTranslation = sentenceTranslation
    self.sourceApplicationName = sourceApplicationName
    self.encounteredAt = encounteredAt
  }
}

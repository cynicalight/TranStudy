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
    sourceApplicationName: String
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
  }
}

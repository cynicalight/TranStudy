import Foundation

struct LearningDataArchive: Codable, Equatable, Sendable {
  static let currentFormatVersion = 1

  let formatVersion: Int
  let exportedAt: Date
  let items: [Item]

  init(
    formatVersion: Int = currentFormatVersion,
    exportedAt: Date,
    items: [Item]
  ) {
    self.formatVersion = formatVersion
    self.exportedAt = exportedAt
    self.items = items
  }

  struct Item: Codable, Equatable, Sendable {
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
    let lastEncounteredAt: Date
    let userNote: String
    let nextReviewAt: Date?
    let isPaused: Bool
    let archivedAt: Date?
    let reviewIntervalDays: Double
    let reviewEase: Double
    let reviewCount: Int
    let lapseCount: Int
    var reviewPhase: ReviewPhase? = nil
    var reviewBaseIntervalDays: Double? = nil
    let encounters: [Encounter]
    let customExamples: [CustomExample]
    let reviewEvents: [ReviewEvent]
  }

  struct Encounter: Codable, Equatable, Sendable {
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

  struct CustomExample: Codable, Equatable, Sendable {
    let id: UUID
    let englishText: String
    let chineseTranslation: String
  }

  struct ReviewEvent: Codable, Equatable, Sendable {
    let id: UUID
    let rating: ReviewRating
    let reviewedAt: Date
    let previousReviewAt: Date?
    let nextReviewAt: Date
    let intervalDays: Double
  }
}

struct LearningDataImportSummary: Equatable, Sendable {
  let importedItemCount: Int
  let mergedItemCount: Int
}

enum LearningDataArchiveError: Error {
  case unsupportedFormatVersion(Int)
}

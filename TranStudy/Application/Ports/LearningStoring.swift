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
}

@MainActor
protocol LearningStoring {
  func summary() async throws -> LearningSummary
  func add(_ addition: LearningAddition) async throws
  func items() async throws -> [LearningItem]
}

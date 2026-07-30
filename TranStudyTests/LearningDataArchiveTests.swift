import Foundation
import SwiftData
import Testing

@testable import TranStudy

@MainActor
struct LearningDataArchiveTests {
  @Test("export preserves learning history and archive metadata")
  func exportPreservesLearningHistory() async throws {
    let (store, _) = try makeStore()
    let exportedAt = Date(timeIntervalSince1970: 9_000)
    try await store.importArchive(fixtureArchive(nextReviewAt: Date(timeIntervalSince1970: 2_000)))

    let archive = try await store.exportArchive(exportedAt: exportedAt)
    let item = try #require(archive.items.first)

    #expect(archive.formatVersion == LearningDataArchive.currentFormatVersion)
    #expect(archive.exportedAt == exportedAt)
    #expect(item.encounters.count == 1)
    #expect(item.customExamples.count == 1)
    #expect(item.reviewEvents.count == 1)
    #expect(item.reviewCount == 1)
  }

  @Test("importing the same archive twice does not duplicate nested data")
  func repeatedImportIsIdempotent() async throws {
    let (store, _) = try makeStore()
    let archive = fixtureArchive(nextReviewAt: Date(timeIntervalSince1970: 2_000))

    _ = try await store.importArchive(archive)
    _ = try await store.importArchive(archive)

    let exported = try await store.exportArchive(exportedAt: Date())
    let item = try #require(exported.items.first)
    #expect(exported.items.count == 1)
    #expect(item.encounters.count == 1)
    #expect(item.customExamples.count == 1)
    #expect(item.reviewEvents.count == 1)
  }

  @Test("sentence identity and example content prevent duplicate imported cards")
  func importDeduplicatesSentenceCardsAndExamples() async throws {
    let (store, _) = try makeStore()
    _ = try await store.importArchive(
      fixtureArchive(nextReviewAt: Date(timeIntervalSince1970: 2_000))
    )
    _ = try await store.importArchive(
      fixtureArchive(
        nextReviewAt: Date(timeIntervalSince1970: 2_000),
        itemID: UUID(uuidString: "EEEEEEEE-EEEE-EEEE-EEEE-EEEEEEEEEEEE")!,
        encounterID: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!,
        exampleID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        reviewEventID: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
      )
    )

    let archive = try await store.exportArchive(exportedAt: Date())
    let item = try #require(archive.items.first)
    #expect(archive.items.count == 1)
    #expect(item.encounters.count == 1)
    #expect(item.customExamples.count == 1)
  }

  @Test("a single imported item cannot create duplicate examples")
  func importDeduplicatesExamplesInsideOneItem() async throws {
    let (store, _) = try makeStore()
    _ = try await store.importArchive(
      fixtureArchive(
        nextReviewAt: Date(timeIntervalSince1970: 2_000),
        includesDuplicateExample: true
      )
    )

    let item = try #require(
      try await store.exportArchive(exportedAt: Date()).items.first
    )
    #expect(item.customExamples.count == 1)
  }

  @Test("import never postpones an existing review date")
  func importKeepsEarlierReviewDate() async throws {
    let (store, _) = try makeStore()
    let earlierDate = Date(timeIntervalSince1970: 1_000)
    var earlierArchive = fixtureArchive(nextReviewAt: earlierDate)
    _ = try await store.importArchive(earlierArchive)

    earlierArchive = fixtureArchive(nextReviewAt: Date(timeIntervalSince1970: 5_000))
    _ = try await store.importArchive(earlierArchive)

    #expect(try await store.items().first?.nextReviewAt == earlierDate)
  }

  @Test("clearing learning data cascades every related record")
  func clearingLearningDataCascadesRelationships() async throws {
    let (store, container) = try makeStore()
    _ = try await store.importArchive(
      fixtureArchive(nextReviewAt: Date(timeIntervalSince1970: 2_000))
    )

    try await store.deleteAllLearningData()

    let context = ModelContext(container)
    #expect(try context.fetch(FetchDescriptor<LearningRecord>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<LearningEncounterRecord>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<LearningCustomExampleRecord>()).isEmpty)
    #expect(try context.fetch(FetchDescriptor<ReviewEventRecord>()).isEmpty)
  }

  private func makeStore() throws -> (SwiftDataLearningStore, ModelContainer) {
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return (SwiftDataLearningStore(container: container), container)
  }

  private func fixtureArchive(
    nextReviewAt: Date,
    itemID: UUID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
    encounterID: UUID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
    exampleID: UUID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
    reviewEventID: UUID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!,
    includesDuplicateExample: Bool = false
  ) -> LearningDataArchive {
    var examples = [
      LearningDataArchive.CustomExample(
        id: exampleID,
        englishText: "Always keep moving forward.",
        chineseTranslation: "始终继续前进。"
      )
    ]
    if includesDuplicateExample {
      examples.append(
        LearningDataArchive.CustomExample(
          id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
          englishText: "Always  keep moving forward.",
          chineseTranslation: "始终继续前进。"
        )
      )
    }
    return LearningDataArchive(
      exportedAt: Date(timeIntervalSince1970: 8_000),
      items: [
        LearningDataArchive.Item(
          id: itemID,
          kind: .sentence,
          sourceText: "Keep moving forward.",
          canonicalForm: "Keep moving forward.",
          pronunciation: "",
          partOfSpeech: "",
          contextualMeaning: "",
          exampleSentence: "Keep moving forward.",
          sentenceTranslation: "继续前进。",
          sourceApplicationName: "Safari",
          createdAt: Date(timeIntervalSince1970: 500),
          lastEncounteredAt: Date(timeIntervalSince1970: 500),
          userNote: "Test note",
          nextReviewAt: nextReviewAt,
          isPaused: false,
          archivedAt: nil,
          reviewIntervalDays: 3,
          reviewEase: 2.5,
          reviewCount: 1,
          lapseCount: 0,
          encounters: [
            LearningDataArchive.Encounter(
              id: encounterID,
              sourceText: "Keep moving forward.",
              pronunciation: "",
              partOfSpeech: "",
              contextualMeaning: "",
              exampleSentence: "Keep moving forward.",
              sentenceTranslation: "继续前进。",
              sourceApplicationName: "Safari",
              encounteredAt: Date(timeIntervalSince1970: 500)
            )
          ],
          customExamples: examples,
          reviewEvents: [
            LearningDataArchive.ReviewEvent(
              id: reviewEventID,
              rating: .remembered,
              reviewedAt: Date(timeIntervalSince1970: 700),
              previousReviewAt: nil,
              nextReviewAt: nextReviewAt,
              intervalDays: 3
            )
          ]
        )
      ]
    )
  }
}

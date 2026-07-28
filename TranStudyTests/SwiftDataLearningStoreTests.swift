import Foundation
import SwiftData
import Testing

@testable import TranStudy

@MainActor
struct SwiftDataLearningStoreTests {
  @Test("joined learning survives reopening the SwiftData store")
  func joinedLearningSurvivesReopeningStore() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let databaseURL = directory.appending(path: "TranStudy.store")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }

    let addition = LearningAddition(
      draft: TranslationDraft(
        sourceText: "ran",
        canonicalForm: "run",
        pronunciation: "/ræn/",
        partOfSpeech: "verb",
        contextualMeaning: "奔跑",
        exampleSentence: "She ran home.",
        sentenceTranslation: "她跑回了家。"
      ),
      sourceApplicationName: "剪贴板",
      createdAt: Date(timeIntervalSince1970: 1_234)
    )

    do {
      let container = try makeContainer(at: databaseURL)
      let store = SwiftDataLearningStore(container: container)
      try await store.add(addition)
    }

    let reopenedContainer = try makeContainer(at: databaseURL)
    let reopenedStore = SwiftDataLearningStore(container: reopenedContainer)
    let items = try await reopenedStore.items()
    let item = try #require(items.first)

    #expect(items.count == 1)
    #expect(item.sourceText == "ran")
    #expect(item.canonicalForm == "run")
    #expect(item.pronunciation == "/ræn/")
    #expect(item.partOfSpeech == "verb")
    #expect(item.contextualMeaning == "奔跑")
    #expect(item.exampleSentence == "She ran home.")
    #expect(item.sentenceTranslation == "她跑回了家。")
    #expect(item.sourceApplicationName == "剪贴板")
    #expect(item.createdAt == Date(timeIntervalSince1970: 1_234))
  }

  @Test("normalized canonical forms merge while preserving every encounter")
  func normalizedCanonicalFormsMergeEncounters() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let databaseURL = directory.appending(path: "TranStudy.store")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let container = try makeContainer(at: databaseURL)
    let store = SwiftDataLearningStore(container: container)

    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "ran",
          canonicalForm: "Run",
          pronunciation: "/ræn/",
          partOfSpeech: "verb",
          contextualMeaning: "跑",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她跑回了家。"
        ),
        sourceApplicationName: "Safari",
        createdAt: Date(timeIntervalSince1970: 1_000),
        nextReviewAt: Date(timeIntervalSince1970: 4_000),
        isPaused: true
      ))
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "running",
          canonicalForm: " run ",
          pronunciation: "/ˈrʌnɪŋ/",
          partOfSpeech: "noun",
          contextualMeaning: "跑步",
          exampleSentence: "Running clears my mind.",
          sentenceTranslation: "跑步让我的头脑清醒。"
        ),
        sourceApplicationName: "Preview",
        createdAt: Date(timeIntervalSince1970: 2_000),
        nextReviewAt: Date(timeIntervalSince1970: 3_500),
        isPaused: false
      ))
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "runs",
          canonicalForm: "RUN",
          pronunciation: "/rʌnz/",
          partOfSpeech: "verb",
          contextualMeaning: "经营",
          exampleSentence: "She runs a small studio.",
          sentenceTranslation: "她经营一家小工作室。"
        ),
        sourceApplicationName: "TextEdit",
        createdAt: Date(timeIntervalSince1970: 3_000)
      ))

    let reopenedContainer = try makeContainer(at: databaseURL)
    let reopenedStore = SwiftDataLearningStore(container: reopenedContainer)
    let items = try await reopenedStore.items()
    let item = try #require(items.first)

    #expect(items.count == 1)
    #expect(item.canonicalForm == "Run")
    #expect(item.encounters.map(\.sourceText) == ["runs", "running", "ran"])
    #expect(item.encounters.map(\.partOfSpeech) == ["verb", "noun", "verb"])
    #expect(item.encounters.map(\.contextualMeaning) == ["经营", "跑步", "跑"])
    #expect(
      item.encounters.map(\.sourceApplicationName)
        == ["TextEdit", "Preview", "Safari"]
    )
    #expect(
      item.encounters.map(\.encounteredAt)
        == [
          Date(timeIntervalSince1970: 3_000),
          Date(timeIntervalSince1970: 2_000),
          Date(timeIntervalSince1970: 1_000),
        ])
    #expect(item.nextReviewAt == Date(timeIntervalSince1970: 3_500))
    #expect(item.isPaused == false)
  }

  @Test("renaming to an existing canonical form requires confirmation before merging")
  func canonicalCorrectionRequiresConfirmationBeforeMerge() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let databaseURL = directory.appending(path: "TranStudy.store")
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let container = try makeContainer(at: databaseURL)
    let store = SwiftDataLearningStore(container: container)
    let earlierReview = Date(timeIntervalSince1970: 3_000)
    let laterReview = Date(timeIntervalSince1970: 4_000)

    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "ran",
          canonicalForm: "run",
          pronunciation: "/ræn/",
          partOfSpeech: "verb",
          contextualMeaning: "跑",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她跑回了家。"
        ),
        sourceApplicationName: "Safari",
        createdAt: Date(timeIntervalSince1970: 1_000),
        nextReviewAt: laterReview,
        isPaused: true
      ))
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "sprinted",
          canonicalForm: "sprint",
          pronunciation: "/sprɪntɪd/",
          partOfSpeech: "verb",
          contextualMeaning: "冲刺",
          exampleSentence: "He sprinted to the station.",
          sentenceTranslation: "他冲向车站。"
        ),
        sourceApplicationName: "Preview",
        createdAt: Date(timeIntervalSince1970: 2_000),
        nextReviewAt: earlierReview,
        isPaused: false
      ))
    let sourceItem = try #require(
      try await store.items().first(where: { $0.canonicalForm == "sprint" })
    )

    let proposedResult = try await store.updateCanonicalForm(
      itemID: sourceItem.id,
      canonicalForm: "run",
      confirmMerge: false
    )

    #expect(
      proposedResult
        == .requiresConfirmation(
          LearningMergeSummary(
            existingItemID: try #require(
              try await store.items().first(where: { $0.canonicalForm == "run" })?.id
            ),
            canonicalForm: "run",
            existingEncounterCount: 1,
            incomingSourceText: "sprinted"
          )))
    #expect(try await store.items().count == 2)

    let confirmedResult = try await store.updateCanonicalForm(
      itemID: sourceItem.id,
      canonicalForm: "run",
      confirmMerge: true
    )
    let reopenedContainer = try makeContainer(at: databaseURL)
    let reopenedStore = SwiftDataLearningStore(container: reopenedContainer)
    let items = try await reopenedStore.items()
    let mergedItem = try #require(items.first)

    #expect(confirmedResult == .merged)
    #expect(items.count == 1)
    #expect(mergedItem.encounters.map(\.sourceText) == ["sprinted", "ran"])
    #expect(mergedItem.nextReviewAt == earlierReview)
    #expect(mergedItem.isPaused == false)
  }

  @Test("legacy duplicate records consolidate without losing their contexts")
  func legacyDuplicateRecordsConsolidate() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      configurations: configuration
    )
    let context = ModelContext(container)
    context.insert(
      LearningRecord(
        createdAt: Date(timeIntervalSince1970: 1_000),
        sourceText: "ran",
        canonicalForm: "run",
        pronunciation: "/ræn/",
        partOfSpeech: "verb",
        contextualMeaning: "跑",
        exampleSentence: "She ran home.",
        sentenceTranslation: "她跑回了家。",
        sourceApplicationName: "Safari",
        nextReviewAt: Date(timeIntervalSince1970: 4_000),
        isPaused: true
      ))
    context.insert(
      LearningRecord(
        createdAt: Date(timeIntervalSince1970: 2_000),
        sourceText: "running",
        canonicalForm: "RUN",
        pronunciation: "/ˈrʌnɪŋ/",
        partOfSpeech: "noun",
        contextualMeaning: "跑步",
        exampleSentence: "Running clears my mind.",
        sentenceTranslation: "跑步让我的头脑清醒。",
        sourceApplicationName: "Preview",
        nextReviewAt: Date(timeIntervalSince1970: 3_000),
        isPaused: false
      ))
    try context.save()

    let store = SwiftDataLearningStore(container: container)
    let items = try await store.items()
    let item = try #require(items.first)

    #expect(items.count == 1)
    #expect(item.encounters.map(\.sourceText) == ["running", "ran"])
    #expect(item.nextReviewAt == Date(timeIntervalSince1970: 3_000))
    #expect(item.isPaused == false)
  }

  @Test("an older encounter does not replace the latest library snapshot")
  func olderEncounterPreservesLatestSnapshot() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)

    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "runs",
          canonicalForm: "run",
          pronunciation: "/rʌnz/",
          partOfSpeech: "verb",
          contextualMeaning: "经营",
          exampleSentence: "She runs a studio.",
          sentenceTranslation: "她经营一家工作室。"
        ),
        sourceApplicationName: "TextEdit",
        createdAt: Date(timeIntervalSince1970: 2_000)
      ))
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "ran",
          canonicalForm: "run",
          pronunciation: "/ræn/",
          partOfSpeech: "verb",
          contextualMeaning: "跑",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她跑回了家。"
        ),
        sourceApplicationName: "Safari",
        createdAt: Date(timeIntervalSince1970: 1_000)
      ))

    let item = try #require(try await store.items().first)

    #expect(item.sourceText == "runs")
    #expect(item.contextualMeaning == "经营")
    #expect(item.sourceApplicationName == "TextEdit")
    #expect(item.encounters.map(\.sourceText) == ["runs", "ran"])
  }

  @Test("an empty canonical form is rejected instead of creating a duplicate bucket")
  func emptyCanonicalFormIsRejected() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let addition = LearningAddition(
      draft: TranslationDraft(
        sourceText: "ran",
        canonicalForm: "   ",
        pronunciation: "/ræn/",
        partOfSpeech: "verb",
        contextualMeaning: "跑",
        exampleSentence: "She ran home.",
        sentenceTranslation: "她跑回了家。"
      ),
      sourceApplicationName: "Safari",
      createdAt: Date(timeIntervalSince1970: 1_000)
    )

    await #expect(throws: LearningStoreError.self) {
      try await store.add(addition)
    }
    #expect(try await store.items().isEmpty)
  }

  private func makeContainer(at url: URL) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: url)
    return try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      configurations: configuration
    )
  }
}

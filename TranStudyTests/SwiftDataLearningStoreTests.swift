import Foundation
import SwiftData
import Testing

@testable import TranStudy

@MainActor
struct SwiftDataLearningStoreTests {
  @Test("cards scheduled later today are available for review")
  func cardsScheduledLaterTodayAreAvailableForReview() async throws {
    let store = try makeInMemoryStore()
    let reviewTime = Date(timeIntervalSince1970: 100_000)
    let laterToday = reviewTime.addingTimeInterval(3_600)

    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "running",
          canonicalForm: "run",
          pronunciation: "/rʌn/",
          partOfSpeech: "verb",
          contextualMeaning: "跑步",
          exampleSentence: "They run every day.",
          sentenceTranslation: "他们每天跑步。"
        ),
        sourceApplicationName: "Safari",
        createdAt: reviewTime.addingTimeInterval(-86_400),
        nextReviewAt: laterToday
      ))

    #expect(try await store.summary(at: reviewTime).dueCount == 1)
    #expect(try await store.dueItems(at: reviewTime).map(\.canonicalForm) == ["run"])
  }

  @Test("archiving cards hides them from learning and restoring preserves schedule")
  func archivingAndRestoringCardsPreservesLearningState() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let dueAt = Date(timeIntervalSince1970: 2_000)

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
        nextReviewAt: dueAt
      ))
    try await store.add(
      LearningAddition(
        kind: .sentence,
        draft: TranslationDraft(
          sourceText: "Keep moving forward.",
          canonicalForm: "Keep moving forward.",
          pronunciation: "",
          partOfSpeech: "",
          contextualMeaning: "",
          exampleSentence: "Keep moving forward.",
          sentenceTranslation: "继续前进。"
        ),
        sourceApplicationName: "Preview",
        createdAt: Date(timeIntervalSince1970: 1_500),
        nextReviewAt: dueAt
      ))
    let originalItems = try await store.items()
    let wordID = try #require(originalItems.first(where: { $0.kind == .word })).id

    try await store.setArchived(
      itemIDs: originalItems.map(\.id),
      archivedAt: Date(timeIntervalSince1970: 3_000)
    )

    #expect(try await store.items().isEmpty)
    #expect(try await store.archivedItems().count == 2)
    #expect(try await store.dueItems(at: dueAt).isEmpty)
    #expect(
      try await store.summary(at: dueAt)
        == LearningSummary(dueCount: 0, wordCount: 0, sentenceCount: 0)
    )

    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "running",
          canonicalForm: "run",
          pronunciation: "/ˈrʌnɪŋ/",
          partOfSpeech: "verb",
          contextualMeaning: "跑步",
          exampleSentence: "They are running.",
          sentenceTranslation: "他们正在跑步。"
        ),
        sourceApplicationName: "TextEdit",
        createdAt: Date(timeIntervalSince1970: 3_500)
      ))

    #expect(try await store.items().isEmpty)
    let archivedWord = try #require(
      try await store.archivedItems().first(where: { $0.id == wordID })
    )
    #expect(archivedWord.encounters.count == 2)

    try await store.setArchived(itemIDs: [wordID], archivedAt: nil)

    let restoredItem = try #require(try await store.items().first)
    #expect(restoredItem.id == wordID)
    #expect(restoredItem.nextReviewAt == dueAt)
    #expect(restoredItem.archivedAt == nil)
    #expect(try await store.archivedItems().count == 1)
    #expect(try await store.dueItems(at: dueAt).map(\.id) == [wordID])
  }

  @Test("deleting a card permanently removes all related learning data")
  func deletingCardCascadesRelatedLearningData() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let reviewDate = Date(timeIntervalSince1970: 10_000)

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
        nextReviewAt: reviewDate
      ))
    let item = try #require(try await store.items().first)
    try await store.updateDetails(
      itemID: item.id,
      details: LearningItemDetailsUpdate(
        pronunciation: "/rʌn/",
        partOfSpeech: "verb",
        contextualMeaning: "奔跑",
        exampleSentence: "I run daily.",
        sentenceTranslation: "我每天跑步。",
        userNote: "",
        customExamples: [
          LearningCustomExample(
            englishText: "Run for your life.",
            chineseTranslation: "快逃。"
          )
        ]
      )
    )
    _ = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: reviewDate
    )

    try await store.delete(itemID: item.id)

    let verificationContext = ModelContext(container)
    #expect(try verificationContext.fetch(FetchDescriptor<LearningRecord>()).isEmpty)
    #expect(try verificationContext.fetch(FetchDescriptor<LearningEncounterRecord>()).isEmpty)
    #expect(try verificationContext.fetch(FetchDescriptor<ReviewEventRecord>()).isEmpty)
    #expect(try verificationContext.fetch(FetchDescriptor<LearningCustomExampleRecord>()).isEmpty)
  }

  @Test("scheduled deletion survives store recreation and leaves review immediately")
  func scheduledDeletionIsDurableAndExcludedFromLearning() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let dueAt = Date(timeIntervalSince1970: 2_000)
    let deleteAt = Date(timeIntervalSince1970: 3_000)
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
        nextReviewAt: dueAt
      ))
    let item = try #require(try await store.items().first)

    try await store.scheduleDeletion(itemID: item.id, deleteAt: deleteAt)

    #expect(try await store.items().isEmpty)
    #expect(try await store.dueItems(at: dueAt).isEmpty)
    #expect(
      try await store.summary(at: dueAt)
        == LearningSummary(dueCount: 0, wordCount: 0, sentenceCount: 0)
    )

    let recreatedStore = SwiftDataLearningStore(container: container)
    #expect(
      try await recreatedStore.pendingDeletion()
        == PendingLearningDeletion(item: item, deleteAt: deleteAt)
    )

    try await recreatedStore.cancelDeletion(itemID: item.id)
    #expect(try await recreatedStore.items().map(\.id) == [item.id])

    try await recreatedStore.scheduleDeletion(itemID: item.id, deleteAt: deleteAt)
    try await recreatedStore.deleteExpiredItems(at: deleteAt.addingTimeInterval(-1))
    #expect(try await recreatedStore.pendingDeletion() != nil)

    try await recreatedStore.deleteExpiredItems(at: deleteAt)
    #expect(try await recreatedStore.pendingDeletion() == nil)
    let verificationContext = ModelContext(container)
    #expect(try verificationContext.fetch(FetchDescriptor<LearningRecord>()).isEmpty)
    #expect(try verificationContext.fetch(FetchDescriptor<LearningEncounterRecord>()).isEmpty)
  }

  @Test("editing learning details preserves encounters and survives reopening")
  func editingLearningDetailsPreservesHistory() async throws {
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
    let exampleID = UUID()
    let itemID: UUID

    do {
      let store = SwiftDataLearningStore(container: try makeContainer(at: databaseURL))
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
      itemID = try #require(try await store.items().first).id

      _ = try await store.updateItem(
        itemID: itemID,
        canonicalForm: "run",
        details: LearningItemDetailsUpdate(
          pronunciation: "/rʌn/",
          partOfSpeech: "verb",
          contextualMeaning: "奔跑；经营",
          exampleSentence: "She runs every morning.",
          sentenceTranslation: "她每天早上跑步。",
          userNote: "注意 run a business 的用法。",
          customExamples: [
            LearningCustomExample(
              id: exampleID,
              englishText: "They run a small café.",
              chineseTranslation: "他们经营一家小咖啡馆。"
            )
          ]
        ))
    }

    let reopenedStore = SwiftDataLearningStore(
      container: try makeContainer(at: databaseURL)
    )
    let item = try #require(try await reopenedStore.items().first)

    #expect(item.id == itemID)
    #expect(item.pronunciation == "/rʌn/")
    #expect(item.contextualMeaning == "奔跑；经营")
    #expect(item.exampleSentence == "She runs every morning.")
    #expect(item.sentenceTranslation == "她每天早上跑步。")
    #expect(item.userNote == "注意 run a business 的用法。")
    #expect(
      item.customExamples
        == [
          LearningCustomExample(
            id: exampleID,
            englishText: "They run a small café.",
            chineseTranslation: "他们经营一家小咖啡馆。"
          )
        ])
    #expect(item.encounters.count == 1)
    #expect(item.encounters.first?.exampleSentence == "She ran home.")
    #expect(item.encounters.first?.sentenceTranslation == "她跑回了家。")
  }

  @Test("editing a legacy learning record first preserves its original encounter")
  func editingLegacyRecordBackfillsOriginalEncounter() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let context = ModelContext(container)
    let record = LearningRecord(
      createdAt: Date(timeIntervalSince1970: 1_000),
      sourceText: "ran",
      canonicalForm: "run",
      pronunciation: "/ræn/",
      partOfSpeech: "verb",
      contextualMeaning: "跑",
      exampleSentence: "She ran home.",
      sentenceTranslation: "她跑回了家。",
      sourceApplicationName: "Safari"
    )
    context.insert(record)
    try context.save()
    let store = SwiftDataLearningStore(container: container)

    try await store.updateDetails(
      itemID: record.id,
      details: LearningItemDetailsUpdate(
        pronunciation: "/rʌn/",
        partOfSpeech: "verb",
        contextualMeaning: "奔跑",
        exampleSentence: "I run daily.",
        sentenceTranslation: "我每天跑步。",
        userNote: "",
        customExamples: []
      ))

    let item = try #require(try await store.items().first)
    #expect(item.exampleSentence == "I run daily.")
    #expect(item.encounters.count == 1)
    #expect(item.encounters.first?.contextualMeaning == "跑")
    #expect(item.encounters.first?.exampleSentence == "She ran home.")
  }

  @Test("confirmed canonical merge keeps the details edited on the source item")
  func canonicalMergeKeepsEditedSourceDetails() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "sprinted",
          canonicalForm: "sprint",
          pronunciation: "/sprɪnt/",
          partOfSpeech: "verb",
          contextualMeaning: "冲刺",
          exampleSentence: "She sprinted first.",
          sentenceTranslation: "她先冲刺了。"
        ),
        sourceApplicationName: "Safari",
        createdAt: Date(timeIntervalSince1970: 1_000)
      ))
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "running",
          canonicalForm: "run",
          pronunciation: "/ˈrʌnɪŋ/",
          partOfSpeech: "verb",
          contextualMeaning: "跑步",
          exampleSentence: "They were running later.",
          sentenceTranslation: "他们后来在跑步。"
        ),
        sourceApplicationName: "Preview",
        createdAt: Date(timeIntervalSince1970: 2_000)
      ))
    let sourceID = try #require(
      try await store.items().first(where: { $0.canonicalForm == "sprint" })
    ).id
    let proposedResult = try await store.updateItem(
      itemID: sourceID,
      canonicalForm: "run",
      details: LearningItemDetailsUpdate(
        pronunciation: "/rʌn/",
        partOfSpeech: "verb",
        contextualMeaning: "用户修正的释义",
        exampleSentence: "User-edited example.",
        sentenceTranslation: "用户修改的例句。",
        userNote: "用户笔记",
        customExamples: []
      ))
    guard case .requiresConfirmation = proposedResult else {
      Issue.record("Expected canonical merge confirmation")
      return
    }

    _ = try await store.updateCanonicalForm(
      itemID: sourceID,
      canonicalForm: "run",
      confirmMerge: true
    )

    let mergedItem = try #require(try await store.items().first)
    #expect(try await store.items().count == 1)
    #expect(mergedItem.contextualMeaning == "用户修正的释义")
    #expect(mergedItem.exampleSentence == "User-edited example.")
    #expect(mergedItem.sentenceTranslation == "用户修改的例句。")
    #expect(mergedItem.userNote == "用户笔记")
    #expect(mergedItem.encounters.count == 2)
  }

  @Test("sentence cards merge only after whitespace normalization")
  func sentenceCardsUseExactWhitespaceNormalizedIdentity() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)

    try await store.add(
      LearningAddition(
        kind: .sentence,
        draft: TranslationDraft(
          sourceText: " She   ran home. ",
          canonicalForm: "She ran home.",
          pronunciation: "",
          partOfSpeech: "",
          contextualMeaning: "",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她跑回了家。"
        ),
        sourceApplicationName: "Safari",
        createdAt: Date(timeIntervalSince1970: 1_000)
      ))
    try await store.add(
      LearningAddition(
        kind: .sentence,
        draft: TranslationDraft(
          sourceText: "She ran home.",
          canonicalForm: "She ran home.",
          pronunciation: "",
          partOfSpeech: "",
          contextualMeaning: "",
          exampleSentence: "She ran home.",
          sentenceTranslation: "她回家了。"
        ),
        sourceApplicationName: "Preview",
        createdAt: Date(timeIntervalSince1970: 2_000)
      ))
    try await store.add(
      LearningAddition(
        kind: .sentence,
        draft: TranslationDraft(
          sourceText: "she ran home.",
          canonicalForm: "she ran home.",
          pronunciation: "",
          partOfSpeech: "",
          contextualMeaning: "",
          exampleSentence: "she ran home.",
          sentenceTranslation: "她跑回了家。"
        ),
        sourceApplicationName: "TextEdit",
        createdAt: Date(timeIntervalSince1970: 3_000)
      ))

    let items = try await store.items()
    let mergedItem = try #require(
      items.first(where: { $0.sourceText == "She ran home." })
    )
    let summary = try await store.summary(at: Date(timeIntervalSince1970: 3_000))
    let review = try await store.recordReview(
      itemID: mergedItem.id,
      rating: .easy,
      reviewedAt: Date(timeIntervalSince1970: 3_000)
    )

    #expect(items.count == 2)
    #expect(items.allSatisfy { $0.kind == .sentence })
    #expect(mergedItem.encounters.count == 2)
    #expect(mergedItem.sourceApplicationName == "Preview")
    #expect(mergedItem.sentenceTranslation == "她回家了。")
    #expect(summary.wordCount == 0)
    #expect(summary.sentenceCount == 2)
    #expect(review.intervalDays == 3)
  }

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
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
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
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
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
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
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

  @Test("new words first become due when joined while paused words stay out of review")
  func newWordsBecomeDueWhenJoinedUnlessPaused() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let joinedAt = Date(timeIntervalSince1970: 10_000)

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
        createdAt: joinedAt
      ))
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "paused",
          canonicalForm: "pause",
          pronunciation: "/pɔːzd/",
          partOfSpeech: "verb",
          contextualMeaning: "暂停",
          exampleSentence: "The music paused.",
          sentenceTranslation: "音乐暂停了。"
        ),
        sourceApplicationName: "Preview",
        createdAt: joinedAt,
        nextReviewAt: joinedAt,
        isPaused: true
      ))

    let dueItems = try await store.dueItems(at: joinedAt)

    #expect(try await store.summary(at: joinedAt).dueCount == 1)
    #expect(dueItems.map(\.canonicalForm) == ["run"])
    #expect(dueItems.first?.nextReviewAt == joinedAt)
  }

  @Test("setting the next review date preserves learned progress")
  func settingNextReviewDatePreservesLearnedProgress() async throws {
    let store = try makeInMemoryStore()
    let firstReviewAt = Date(timeIntervalSince1970: 10_000)
    let item = try await addRun(to: store, createdAt: firstReviewAt)
    _ = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: firstReviewAt
    )
    let correctedReviewAt = Date(timeIntervalSince1970: 20_000)

    try await store.setNextReviewDate(
      itemID: item.id,
      nextReviewAt: correctedReviewAt
    )

    let updatedItem = try #require(try await store.items().first)
    #expect(updatedItem.nextReviewAt == correctedReviewAt)
    #expect(try await store.reviewHistory(itemID: item.id).count == 1)
  }

  @Test("pausing and resuming review preserves the due date")
  func pausingAndResumingReviewPreservesDueDate() async throws {
    let store = try makeInMemoryStore()
    let dueAt = Date(timeIntervalSince1970: 10_000)
    let item = try await addRun(to: store, createdAt: dueAt)

    try await store.setReviewPaused(itemID: item.id, isPaused: true)

    let pausedItem = try #require(try await store.items().first)
    #expect(pausedItem.isPaused)
    #expect(pausedItem.nextReviewAt == dueAt)
    #expect(try await store.dueItems(at: dueAt).isEmpty)

    try await store.setReviewPaused(itemID: item.id, isPaused: false)

    let resumedItem = try #require(try await store.items().first)
    #expect(!resumedItem.isPaused)
    #expect(resumedItem.nextReviewAt == dueAt)
    #expect(try await store.dueItems(at: dueAt).map(\.id) == [item.id])
  }

  @Test("resetting review progress clears history and restores the initial schedule")
  func resettingReviewProgressClearsHistoryAndRestoresInitialSchedule() async throws {
    let store = try makeInMemoryStore()
    let firstReviewAt = Date(timeIntervalSince1970: 10_000)
    let item = try await addRun(to: store, createdAt: firstReviewAt)
    _ = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: firstReviewAt
    )
    try await store.setReviewPaused(itemID: item.id, isPaused: true)
    let resetAt = Date(timeIntervalSince1970: 20_000)

    try await store.resetReviewProgress(itemID: item.id, resetAt: resetAt)

    let resetItem = try #require(try await store.items().first)
    #expect(resetItem.nextReviewAt == resetAt)
    #expect(resetItem.isPaused)
    #expect(try await store.reviewHistory(itemID: item.id).isEmpty)

    try await store.setReviewPaused(itemID: item.id, isPaused: false)
    let result = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: resetAt
    )
    #expect(result.intervalDays == 1)
  }

  private func addRun(
    to store: SwiftDataLearningStore,
    createdAt: Date
  ) async throws -> LearningItem {
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
        createdAt: createdAt
      ))
    return try #require(try await store.items().first)
  }

  @Test("legacy words without a schedule become due from their joined time")
  func legacyWordsWithoutScheduleBecomeDueFromJoinedTime() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let joinedAt = Date(timeIntervalSince1970: 10_000)
    let context = ModelContext(container)
    context.insert(
      LearningRecord(
        createdAt: joinedAt,
        sourceText: "ran",
        canonicalForm: "run",
        pronunciation: "/ræn/",
        partOfSpeech: "verb",
        contextualMeaning: "跑",
        exampleSentence: "She ran home.",
        sentenceTranslation: "她跑回了家。",
        sourceApplicationName: "Safari",
        nextReviewAt: nil
      ))
    try context.save()
    let store = SwiftDataLearningStore(container: container)

    let dueItems = try await store.dueItems(at: joinedAt)
    let reloadedItems = try await SwiftDataLearningStore(container: container).items()

    #expect(try await store.summary(at: joinedAt).dueCount == 1)
    #expect(dueItems.map(\.canonicalForm) == ["run"])
    #expect(reloadedItems.first?.nextReviewAt == joinedAt)
  }

  @Test("first review ratings schedule their reinforcement steps")
  func firstReviewRatingsScheduleReinforcementSteps() async throws {
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
    let reviewDate = Date(timeIntervalSince1970: 100_000)
    let expectations: [(String, ReviewRating, Double)] = [
      ("forget", .forgot, 0),
      ("hard", .hard, 0),
      ("remember", .remembered, 1),
      ("easy", .easy, 3),
    ]

    do {
      let container = try makeContainer(at: databaseURL)
      let store = SwiftDataLearningStore(container: container)
      for (canonicalForm, rating, expectedInterval) in expectations {
        try await store.add(
          LearningAddition(
            draft: TranslationDraft(
              sourceText: canonicalForm,
              canonicalForm: canonicalForm,
              pronunciation: "",
              partOfSpeech: "verb",
              contextualMeaning: canonicalForm,
              exampleSentence: "\(canonicalForm) example",
              sentenceTranslation: "\(canonicalForm) 翻译"
            ),
            sourceApplicationName: "Safari",
            createdAt: reviewDate.addingTimeInterval(-86_400),
            nextReviewAt: reviewDate
          ))
        let item = try #require(
          try await store.items().first(where: { $0.canonicalForm == canonicalForm })
        )

        let result = try await store.recordReview(
          itemID: item.id,
          rating: rating,
          reviewedAt: reviewDate
        )

        #expect(result.intervalDays == expectedInterval)
        #expect(
          result.nextReviewAt
            == reviewDate.addingTimeInterval(expectedInterval * 86_400)
        )
      }

      #expect(try await store.summary(at: reviewDate).dueCount == 2)
      #expect(
        Set(try await store.dueItems(at: reviewDate).map(\.canonicalForm))
          == ["forget", "hard"]
      )
    }

    let reopenedContainer = try makeContainer(at: databaseURL)
    let reopenedStore = SwiftDataLearningStore(container: reopenedContainer)
    let items = try await reopenedStore.items()

    for (canonicalForm, rating, _) in expectations {
      let item = try #require(items.first(where: { $0.canonicalForm == canonicalForm }))
      let history = try await reopenedStore.reviewHistory(itemID: item.id)

      #expect(history.map(\.rating) == [rating])
      #expect(history.map(\.reviewedAt) == [reviewDate])
    }

    let hardItem = try #require(items.first(where: { $0.canonicalForm == "hard" }))
    let hardNextDay = try await reopenedStore.recordReview(
      itemID: hardItem.id,
      rating: .remembered,
      reviewedAt: reviewDate.addingTimeInterval(3_600)
    )
    #expect(hardNextDay.intervalDays == 1)
  }

  @Test("forgotten cards repeat today, then daily until recalled")
  func forgottenCardsRepeatTodayThenDailyUntilRecalled() async throws {
    let store = try makeInMemoryStore()
    let firstReviewAt = Date(timeIntervalSince1970: 100_000)
    let item = try await addRun(to: store, createdAt: firstReviewAt)

    let sameDay = try await store.recordReview(
      itemID: item.id,
      rating: .forgot,
      reviewedAt: firstReviewAt
    )
    let nextDay = try await store.recordReview(
      itemID: item.id,
      rating: .forgot,
      reviewedAt: firstReviewAt.addingTimeInterval(3_600)
    )
    let followingDay = try await store.recordReview(
      itemID: item.id,
      rating: .forgot,
      reviewedAt: nextDay.nextReviewAt
    )
    let recalled = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: followingDay.nextReviewAt
    )

    #expect(sameDay.nextReviewAt == firstReviewAt)
    #expect(nextDay.intervalDays == 1)
    #expect(followingDay.intervalDays == 1)
    #expect(recalled.intervalDays == 3)
  }

  @Test("hard cards repeat today and tomorrow before using the adaptive interval")
  func hardCardsRepeatTodayAndTomorrowBeforeAdaptiveInterval() async throws {
    let store = try makeInMemoryStore()
    let firstReviewAt = Date(timeIntervalSince1970: 100_000)
    let item = try await addRun(to: store, createdAt: firstReviewAt)

    let sameDay = try await store.recordReview(
      itemID: item.id,
      rating: .hard,
      reviewedAt: firstReviewAt
    )
    let nextDay = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: firstReviewAt.addingTimeInterval(3_600)
    )
    let adaptive = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: nextDay.nextReviewAt
    )

    #expect(sameDay.nextReviewAt == firstReviewAt)
    #expect(nextDay.intervalDays == 1)
    #expect(adaptive.intervalDays == 3)
  }

  @Test("forgetting a hard card during today's reinforcement repeats it today")
  func forgettingHardCardDuringSameDayReinforcementRepeatsToday() async throws {
    let store = try makeInMemoryStore()
    let firstReviewAt = Date(timeIntervalSince1970: 100_000)
    let item = try await addRun(to: store, createdAt: firstReviewAt)
    _ = try await store.recordReview(
      itemID: item.id,
      rating: .hard,
      reviewedAt: firstReviewAt
    )
    let forgotAt = firstReviewAt.addingTimeInterval(3_600)

    let repeatedReview = try await store.recordReview(
      itemID: item.id,
      rating: .forgot,
      reviewedAt: forgotAt
    )

    #expect(repeatedReview.intervalDays == 0)
    #expect(repeatedReview.nextReviewAt == forgotAt)
  }

  @Test("remembered and easy cards get one short reinforcement before adaptive intervals")
  func rememberedAndEasyCardsGetOneShortReinforcement() async throws {
    let firstReviewAt = Date(timeIntervalSince1970: 100_000)

    let rememberedStore = try makeInMemoryStore()
    let rememberedItem = try await addRun(to: rememberedStore, createdAt: firstReviewAt)
    let rememberedStep = try await rememberedStore.recordReview(
      itemID: rememberedItem.id,
      rating: .remembered,
      reviewedAt: firstReviewAt
    )
    let rememberedAdaptive = try await rememberedStore.recordReview(
      itemID: rememberedItem.id,
      rating: .remembered,
      reviewedAt: rememberedStep.nextReviewAt
    )

    let easyStore = try makeInMemoryStore()
    let easyItem = try await addRun(to: easyStore, createdAt: firstReviewAt)
    let easyStep = try await easyStore.recordReview(
      itemID: easyItem.id,
      rating: .easy,
      reviewedAt: firstReviewAt
    )
    let easyAdaptive = try await easyStore.recordReview(
      itemID: easyItem.id,
      rating: .easy,
      reviewedAt: easyStep.nextReviewAt
    )

    #expect(rememberedStep.intervalDays == 1)
    #expect(rememberedAdaptive.intervalDays == 3)
    #expect(easyStep.intervalDays == 3)
    #expect(easyAdaptive.intervalDays == 5)
  }

  @Test("short reinforcement steps preserve the growing adaptive interval")
  func reinforcementStepsPreserveGrowingAdaptiveInterval() async throws {
    let store = try makeInMemoryStore()
    let firstReviewAt = Date(timeIntervalSince1970: 100_000)
    let item = try await addRun(to: store, createdAt: firstReviewAt)

    let firstStep = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: firstReviewAt
    )
    let firstAdaptive = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: firstStep.nextReviewAt
    )
    let secondStep = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: firstAdaptive.nextReviewAt
    )
    let secondAdaptive = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: secondStep.nextReviewAt
    )

    #expect(firstStep.intervalDays == 1)
    #expect(firstAdaptive.intervalDays == 3)
    #expect(secondStep.intervalDays == 1)
    #expect(secondAdaptive.intervalDays == 8)
  }

  @Test("summary reports today's reviews and a consecutive-day learning streak")
  func summaryReportsDailyReviewStatistics() async throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container, calendar: calendar)
    let july8 = date(year: 2026, month: 7, day: 8, calendar: calendar)
    let july9 = date(year: 2026, month: 7, day: 9, calendar: calendar)
    let july10 = date(year: 2026, month: 7, day: 10, calendar: calendar)

    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "run",
          canonicalForm: "run",
          pronunciation: "",
          partOfSpeech: "verb",
          contextualMeaning: "跑",
          exampleSentence: "I run.",
          sentenceTranslation: "我跑步。"
        ),
        sourceApplicationName: "Safari",
        createdAt: july8.addingTimeInterval(-86_400),
        nextReviewAt: july8
      ))
    let reviewedWord = try #require(try await store.items().first)
    for reviewDate in [july8, july9, july10] {
      _ = try await store.recordReview(
        itemID: reviewedWord.id,
        rating: .remembered,
        reviewedAt: reviewDate
      )
    }
    try await store.add(
      LearningAddition(
        kind: .sentence,
        draft: TranslationDraft(
          sourceText: "Keep moving.",
          canonicalForm: "Keep moving.",
          pronunciation: "",
          partOfSpeech: "",
          contextualMeaning: "",
          exampleSentence: "Keep moving.",
          sentenceTranslation: "继续前进。"
        ),
        sourceApplicationName: "TextEdit",
        createdAt: july8,
        nextReviewAt: july10
      ))
    try await store.add(
      LearningAddition(
        draft: TranslationDraft(
          sourceText: "paused",
          canonicalForm: "pause",
          pronunciation: "",
          partOfSpeech: "verb",
          contextualMeaning: "暂停",
          exampleSentence: "Pause here.",
          sentenceTranslation: "在这里暂停。"
        ),
        sourceApplicationName: "Preview",
        createdAt: july8,
        nextReviewAt: july10,
        isPaused: true
      ))

    let today = try await store.summary(at: july10.addingTimeInterval(43_200))
    let nextDay = try await store.summary(at: july10.addingTimeInterval(86_400 + 43_200))
    let missedDay = try await store.summary(at: july10.addingTimeInterval(172_800 + 43_200))

    #expect(today.dueCount == 1)
    #expect(today.reviewedTodayCount == 1)
    #expect(today.streakDayCount == 3)
    #expect(today.wordCount == 2)
    #expect(today.sentenceCount == 1)
    #expect(nextDay.reviewedTodayCount == 0)
    #expect(nextDay.streakDayCount == 3)
    #expect(missedDay.streakDayCount == 0)
  }

  @Test("review history records the previous actual review time")
  func reviewHistoryRecordsPreviousActualReviewTime() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let firstReviewDate = Date(timeIntervalSince1970: 100_000)
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
        createdAt: firstReviewDate.addingTimeInterval(-86_400),
        nextReviewAt: firstReviewDate
      ))
    let item = try #require(try await store.items().first)
    let firstResult = try await store.recordReview(
      itemID: item.id,
      rating: .forgot,
      reviewedAt: firstReviewDate
    )
    let secondReviewDate = firstResult.nextReviewAt.addingTimeInterval(300)
    _ = try await store.recordReview(
      itemID: item.id,
      rating: .remembered,
      reviewedAt: secondReviewDate
    )

    let history = try await store.reviewHistory(itemID: item.id)

    #expect(history.map(\.previousReviewAt) == [nil, firstReviewDate])
    #expect(history.map(\.reviewedAt) == [firstReviewDate, secondReviewDate])
  }

  @Test("cards with the same due date keep a deterministic order")
  func sameDueDateUsesDeterministicOrder() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let dueDate = Date(timeIntervalSince1970: 100_000)
    for canonicalForm in ["zebra", "apple", "middle"] {
      try await store.add(
        LearningAddition(
          draft: TranslationDraft(
            sourceText: canonicalForm,
            canonicalForm: canonicalForm,
            pronunciation: "",
            partOfSpeech: "noun",
            contextualMeaning: canonicalForm,
            exampleSentence: "\(canonicalForm) example",
            sentenceTranslation: "\(canonicalForm) 翻译"
          ),
          sourceApplicationName: "Safari",
          createdAt: dueDate.addingTimeInterval(-86_400),
          nextReviewAt: dueDate
        ))
    }
    let firstOrder = try await store.dueItems(at: dueDate).map(\.id)
    let secondOrder = try await store.dueItems(at: dueDate).map(\.id)

    #expect(firstOrder == secondOrder)
    #expect(firstOrder == firstOrder.sorted { $0.uuidString < $1.uuidString })
  }

  @Test("merging reviewed words preserves both histories and the more urgent schedule state")
  func mergingReviewedWordsPreservesHistoryAndUrgentSchedule() async throws {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    let store = SwiftDataLearningStore(container: container)
    let reviewDate = Date(timeIntervalSince1970: 100_000)

    for canonicalForm in ["run", "sprint"] {
      try await store.add(
        LearningAddition(
          draft: TranslationDraft(
            sourceText: canonicalForm,
            canonicalForm: canonicalForm,
            pronunciation: "",
            partOfSpeech: "verb",
            contextualMeaning: canonicalForm,
            exampleSentence: "\(canonicalForm) example",
            sentenceTranslation: "\(canonicalForm) 翻译"
          ),
          sourceApplicationName: "Safari",
          createdAt: reviewDate.addingTimeInterval(-86_400),
          nextReviewAt: reviewDate
        ))
    }
    let runItem = try #require(
      try await store.items().first(where: { $0.canonicalForm == "run" })
    )
    let sprintItem = try #require(
      try await store.items().first(where: { $0.canonicalForm == "sprint" })
    )
    _ = try await store.recordReview(
      itemID: runItem.id,
      rating: .easy,
      reviewedAt: reviewDate
    )
    let urgentResult = try await store.recordReview(
      itemID: sprintItem.id,
      rating: .hard,
      reviewedAt: reviewDate.addingTimeInterval(1)
    )

    _ = try await store.updateCanonicalForm(
      itemID: sprintItem.id,
      canonicalForm: "run",
      confirmMerge: true
    )

    let mergedItem = try #require(try await store.items().first)
    let history = try await store.reviewHistory(itemID: mergedItem.id)
    let nextResult = try await store.recordReview(
      itemID: mergedItem.id,
      rating: .remembered,
      reviewedAt: urgentResult.nextReviewAt
    )

    #expect(mergedItem.nextReviewAt == urgentResult.nextReviewAt)
    #expect(history.map(\.rating) == [.easy, .hard])
    #expect(nextResult.intervalDays == 1)
  }

  private func makeContainer(at url: URL) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: url)
    return try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
  }

  private func date(
    year: Int,
    month: Int,
    day: Int,
    calendar: Calendar
  ) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day))!
  }

  private func makeInMemoryStore() throws -> SwiftDataLearningStore {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
    return SwiftDataLearningStore(container: container)
  }
}

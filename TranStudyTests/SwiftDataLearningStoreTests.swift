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

  private func makeContainer(at url: URL) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: url)
    return try ModelContainer(
      for: LearningRecord.self,
      configurations: configuration
    )
  }
}

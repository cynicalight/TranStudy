import Foundation
import Testing

@testable import TranStudy

@MainActor
struct TranslationCacheStoreTests {
  @Test("translation cache survives service recreation")
  func translationCachePersists() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "TranslationCacheStoreTests-\(UUID().uuidString)")
    let fileURL = directory.appending(path: "translation-cache.json")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let key = TranslationCacheKey(
      configuration: .default,
      request: TranslationRequest(
        sourceText: "ran",
        context: "She ran home.",
        kind: .contextualSelection
      )
    )
    let result = TranslationResult(
      sourceText: "ran",
      canonicalForm: "run",
      pronunciation: "/ræn/",
      partOfSpeech: "verb",
      contextualMeaning: "奔跑",
      exampleSentence: "She ran home.",
      sentenceTranslation: "她跑回了家。"
    )

    let firstStore = FileTranslationCacheStore(fileURL: fileURL)
    firstStore.insert(result, for: key)
    let reopenedStore = FileTranslationCacheStore(fileURL: fileURL)

    #expect(reopenedStore.value(for: key) == result)
  }

  @Test("translation cache can be cleared without touching other app data")
  func translationCacheClearsItsOwnFile() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "TranslationCacheClearTests-\(UUID().uuidString)")
    let fileURL = directory.appending(path: "translation-cache.json")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = FileTranslationCacheStore(fileURL: fileURL)
    let key = TranslationCacheKey(
      configuration: .default,
      request: TranslationRequest(sourceText: "test")
    )
    store.insert(
      TranslationResult(
        sourceText: "test",
        canonicalForm: "test",
        pronunciation: "",
        partOfSpeech: "",
        contextualMeaning: "测试",
        exampleSentence: "A test.",
        sentenceTranslation: "一个测试。"
      ),
      for: key
    )

    try store.clear()

    #expect(store.value(for: key) == nil)
    #expect(!FileManager.default.fileExists(atPath: fileURL.path))
  }
}

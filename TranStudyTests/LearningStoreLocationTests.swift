import Foundation
import SwiftData
import Testing

@testable import TranStudy

struct LearningStoreLocationTests {
  @Test("learning store uses the TranStudy application support directory")
  func stableApplicationSupportLocation() throws {
    let applicationSupportDirectory = FileManager.default.temporaryDirectory
      .appending(path: "LearningStoreLocationTests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: applicationSupportDirectory)
    }

    let storeURL = try LearningStoreLocation.preparePersistentStoreURL(
      applicationSupportDirectory: applicationSupportDirectory
    )

    #expect(
      storeURL
        == applicationSupportDirectory
        .appending(path: "TranStudy", directoryHint: .isDirectory)
        .appending(path: "learning.store")
    )
  }

  @Test("legacy default store is copied without deleting the original")
  func migratesLegacyStoreWithoutDeletingIt() throws {
    let applicationSupportDirectory = FileManager.default.temporaryDirectory
      .appending(path: "LearningStoreMigrationTests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: applicationSupportDirectory)
    }
    try FileManager.default.createDirectory(
      at: applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    let legacyStoreURL = applicationSupportDirectory.appending(path: "default.store")
    let legacyWALURL = applicationSupportDirectory.appending(path: "default.store-wal")
    try Data("legacy-store".utf8).write(to: legacyStoreURL)
    try Data("legacy-wal".utf8).write(to: legacyWALURL)

    let storeURL = try LearningStoreLocation.preparePersistentStoreURL(
      applicationSupportDirectory: applicationSupportDirectory
    )

    #expect(try Data(contentsOf: storeURL) == Data("legacy-store".utf8))
    #expect(
      try Data(contentsOf: URL(fileURLWithPath: storeURL.path + "-wal"))
        == Data("legacy-wal".utf8)
    )
    #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
    #expect(FileManager.default.fileExists(atPath: legacyWALURL.path))
  }

  @Test("existing learning store is never overwritten by a legacy store")
  func preservesExistingLearningStore() throws {
    let applicationSupportDirectory = FileManager.default.temporaryDirectory
      .appending(path: "LearningStoreExistingTests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: applicationSupportDirectory)
    }
    let storeDirectory =
      applicationSupportDirectory
      .appending(path: "TranStudy", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: storeDirectory,
      withIntermediateDirectories: true
    )
    let storeURL = storeDirectory.appending(path: "learning.store")
    let legacyStoreURL = applicationSupportDirectory.appending(path: "default.store")
    try Data("current-store".utf8).write(to: storeURL)
    try Data("legacy-store".utf8).write(to: legacyStoreURL)

    let preparedURL = try LearningStoreLocation.preparePersistentStoreURL(
      applicationSupportDirectory: applicationSupportDirectory
    )

    #expect(preparedURL == storeURL)
    #expect(try Data(contentsOf: storeURL) == Data("current-store".utf8))
  }

  @Test("records remain readable after migrating a real SwiftData store")
  @MainActor
  func migratesSwiftDataRecords() throws {
    let applicationSupportDirectory = FileManager.default.temporaryDirectory
      .appending(path: "LearningStoreSwiftDataTests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: applicationSupportDirectory)
    }
    try FileManager.default.createDirectory(
      at: applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    let legacyStoreURL = applicationSupportDirectory.appending(path: "default.store")
    try writeLegacyRecord(to: legacyStoreURL)

    let storeURL = try LearningStoreLocation.preparePersistentStoreURL(
      applicationSupportDirectory: applicationSupportDirectory
    )
    let container = try makeContainer(at: storeURL)
    let records = try ModelContext(container).fetch(FetchDescriptor<LearningRecord>())

    #expect(records.count == 1)
    #expect(records.first?.sourceText == "persistent")
    #expect(records.first?.contextualMeaning == "持久的")
    #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
  }

  @Test("an orphaned destination WAL cannot mark migration as complete")
  func replacesOrphanedDestinationWAL() throws {
    let applicationSupportDirectory = FileManager.default.temporaryDirectory
      .appending(path: "LearningStoreInterruptedTests-\(UUID().uuidString)")
    defer {
      try? FileManager.default.removeItem(at: applicationSupportDirectory)
    }
    let storeDirectory =
      applicationSupportDirectory
      .appending(path: "TranStudy", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: storeDirectory,
      withIntermediateDirectories: true
    )
    let legacyStoreURL = applicationSupportDirectory.appending(path: "default.store")
    let legacyWALURL = applicationSupportDirectory.appending(path: "default.store-wal")
    let storeWALURL = storeDirectory.appending(path: "learning.store-wal")
    try Data("legacy-store".utf8).write(to: legacyStoreURL)
    try Data("legacy-wal".utf8).write(to: legacyWALURL)
    try Data("interrupted-wal".utf8).write(to: storeWALURL)

    let storeURL = try LearningStoreLocation.preparePersistentStoreURL(
      applicationSupportDirectory: applicationSupportDirectory
    )

    #expect(try Data(contentsOf: storeURL) == Data("legacy-store".utf8))
    #expect(try Data(contentsOf: storeWALURL) == Data("legacy-wal".utf8))
  }

  @MainActor
  private func writeLegacyRecord(to storeURL: URL) throws {
    let container = try makeContainer(at: storeURL)
    let context = ModelContext(container)
    context.insert(
      LearningRecord(
        sourceText: "persistent",
        canonicalForm: "persistent",
        pronunciation: "/pərˈsɪstənt/",
        partOfSpeech: "adjective",
        contextualMeaning: "持久的",
        exampleSentence: "The record should persist.",
        sentenceTranslation: "这条记录应该保留下来。",
        sourceApplicationName: "Tests"
      )
    )
    try context.save()
  }

  @MainActor
  private func makeContainer(at storeURL: URL) throws -> ModelContainer {
    let configuration = ModelConfiguration(url: storeURL)
    return try ModelContainer(
      for: LearningRecord.self,
      LearningEncounterRecord.self,
      ReviewEventRecord.self,
      LearningCustomExampleRecord.self,
      configurations: configuration
    )
  }
}

import Foundation
import Testing

@testable import TranStudy

@MainActor
struct DiagnosticLogStoreTests {
  @Test("diagnostic archive contains only bounded metadata")
  func diagnosticArchiveContainsOnlyMetadata() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "DiagnosticLogStoreTests-\(UUID().uuidString)")
    let fileURL = directory.appending(path: "diagnostics.json")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = FileDiagnosticLogStore(fileURL: fileURL)

    store.record(
      stage: .translationFailed,
      sourceApplicationIdentifier: "com.apple.Safari",
      errorType: .network,
      durationMilliseconds: 240
    )

    let archive = store.exportArchive(exportedAt: Date(timeIntervalSince1970: 1_000))
    let data = try JSONEncoder.tranStudy.encode(archive)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(archive.events.count == 1)
    #expect(json.contains("com.apple.Safari"))
    #expect(!json.contains("selectedText"))
    #expect(!json.contains("timestamp"))
    #expect(!json.contains("context"))
    #expect(!json.contains("apiKey"))
    #expect(!json.contains("rawResponse"))
  }
}

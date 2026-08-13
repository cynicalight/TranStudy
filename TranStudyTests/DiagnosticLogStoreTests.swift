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

  @Test("failed translation export explains the request and validation failure")
  func failedTranslationExportExplainsFailure() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: "DiagnosticLogStoreTests-\(UUID().uuidString)")
    let fileURL = directory.appending(path: "diagnostics.json")
    defer {
      try? FileManager.default.removeItem(at: directory)
    }
    let store = FileDiagnosticLogStore(fileURL: fileURL)

    store.recordTranslation(
      stage: .translationFailed,
      sourceApplicationIdentifier: "company.thebrowser.Browser",
      errorType: .invalidEnglishResponse,
      durationMilliseconds: 2_376,
      details: DiagnosticTranslationDetails(
        provider: "openAICompatible",
        model: "gpt-5-mini",
        requestKind: .contextualSelection,
        failureReason: .exampleSentenceDoesNotMatchSelectionContext,
        missingResponseFields: nil,
        httpStatusCode: 200
      )
    )

    let archive = store.exportArchive(exportedAt: Date(timeIntervalSince1970: 1_000))
    let event = try #require(archive.events.first)
    #expect(event.provider == "openAICompatible")
    #expect(event.model == "gpt-5-mini")
    #expect(event.requestKind == .contextualSelection)
    #expect(event.failureReason == .exampleSentenceDoesNotMatchSelectionContext)
    #expect(event.missingResponseFields == nil)
    #expect(event.httpStatusCode == 200)

    let data = try JSONEncoder.tranStudy.encode(archive)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(!json.contains("selected text"))
    #expect(!json.contains("raw model response"))
    #expect(!json.contains("secret-key"))
  }
}

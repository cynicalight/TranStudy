import Foundation

@MainActor
final class FileDiagnosticLogStore: DiagnosticLogging {
  private let fileURL: URL
  private let maximumEventCount: Int
  private var events: [DiagnosticEvent]

  init(
    fileURL: URL = FileDiagnosticLogStore.defaultFileURL,
    maximumEventCount: Int = 500
  ) {
    self.fileURL = fileURL
    self.maximumEventCount = maximumEventCount
    events = Self.load(from: fileURL)
  }

  func record(
    stage: DiagnosticStage,
    sourceApplicationIdentifier: String?,
    errorType: DiagnosticErrorType?,
    durationMilliseconds: Int?
  ) {
    append(
      stage: stage,
      sourceApplicationIdentifier: sourceApplicationIdentifier,
      errorType: errorType,
      durationMilliseconds: durationMilliseconds,
      details: nil
    )
  }

  func recordTranslation(
    stage: DiagnosticStage,
    sourceApplicationIdentifier: String?,
    errorType: DiagnosticErrorType?,
    durationMilliseconds: Int?,
    details: DiagnosticTranslationDetails
  ) {
    append(
      stage: stage,
      sourceApplicationIdentifier: sourceApplicationIdentifier,
      errorType: errorType,
      durationMilliseconds: durationMilliseconds,
      details: details
    )
  }

  private func append(
    stage: DiagnosticStage,
    sourceApplicationIdentifier: String?,
    errorType: DiagnosticErrorType?,
    durationMilliseconds: Int?,
    details: DiagnosticTranslationDetails?
  ) {
    events.append(
      DiagnosticEvent(
        appVersion: Self.appVersion,
        systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        sourceApplicationIdentifier: sourceApplicationIdentifier,
        stage: stage,
        errorType: errorType,
        durationMilliseconds: durationMilliseconds,
        provider: details?.provider,
        model: details?.model,
        requestKind: details?.requestKind,
        failureReason: details?.failureReason,
        missingResponseFields: details?.missingResponseFields,
        httpStatusCode: details?.httpStatusCode
      )
    )
    if events.count > maximumEventCount {
      events.removeFirst(events.count - maximumEventCount)
    }
    persist()
  }

  private static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "unknown"
  }

  func exportArchive(exportedAt: Date) -> DiagnosticArchive {
    DiagnosticArchive(
      formatVersion: DiagnosticArchive.currentFormatVersion,
      exportedAt: exportedAt,
      events: events
    )
  }

  private func persist() {
    do {
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder.tranStudy.encode(events)
      try data.write(to: fileURL, options: .atomic)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: fileURL.path
      )
    } catch {
      // Diagnostics are best-effort and never affect app behavior.
    }
  }

  private static func load(from fileURL: URL) -> [DiagnosticEvent] {
    guard let data = try? Data(contentsOf: fileURL) else {
      return []
    }
    return (try? JSONDecoder.tranStudy.decode([DiagnosticEvent].self, from: data)) ?? []
  }

  private static var defaultFileURL: URL {
    let root =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return
      root
      .appending(path: "com.cynicalight.TranStudy", directoryHint: .isDirectory)
      .appending(path: "diagnostics.json")
  }
}

extension JSONEncoder {
  static var tranStudy: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
  }
}

extension JSONDecoder {
  static var tranStudy: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

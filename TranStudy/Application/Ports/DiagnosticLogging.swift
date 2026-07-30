import Foundation

enum DiagnosticStage: String, Codable, Sendable {
  case translationStarted
  case translationSucceeded
  case translationFailed
  case learningDataExported
  case learningDataImported
  case learningDataCleared
  case translationCacheCleared
}

enum DiagnosticErrorType: String, Codable, Sendable {
  case configuration
  case authentication
  case quota
  case rateLimited
  case requestRejected
  case timeout
  case network
  case invalidResponse
  case storage
  case unknown
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
  let appVersion: String
  let systemVersion: String
  let sourceApplicationIdentifier: String?
  let stage: DiagnosticStage
  let errorType: DiagnosticErrorType?
  let durationMilliseconds: Int?
}

struct DiagnosticArchive: Codable, Equatable, Sendable {
  static let currentFormatVersion = 1

  let formatVersion: Int
  let exportedAt: Date
  let events: [DiagnosticEvent]
}

@MainActor
protocol DiagnosticLogging {
  func record(
    stage: DiagnosticStage,
    sourceApplicationIdentifier: String?,
    errorType: DiagnosticErrorType?,
    durationMilliseconds: Int?
  )
  func exportArchive(exportedAt: Date) -> DiagnosticArchive
}

extension DiagnosticLogging {
  func record(
    stage: DiagnosticStage,
    sourceApplicationIdentifier: String? = nil,
    errorType: DiagnosticErrorType? = nil,
    durationMilliseconds: Int? = nil
  ) {}

  func exportArchive(exportedAt: Date) -> DiagnosticArchive {
    DiagnosticArchive(formatVersion: 1, exportedAt: exportedAt, events: [])
  }
}

import Foundation

enum DiagnosticStage: String, Codable, Sendable {
  case translationStarted
  case translationSucceeded
  case translationFailed
  case learningAdditionStarted
  case learningAdditionSucceeded
  case learningAdditionFailed
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
  case malformedResponse
  case unexpectedResponseKind
  case missingResponseContent
  case invalidEnglishResponse
  case invalidChineseResponse
  case storage
  case unknown
}

enum DiagnosticTranslationRequestKind: String, Codable, Sendable {
  case wordOrPhrase
  case contextualSelection
  case longText

  init(_ requestKind: TranslationRequestKind) {
    switch requestKind {
    case .wordOrPhrase:
      self = .wordOrPhrase
    case .contextualSelection:
      self = .contextualSelection
    case .longText:
      self = .longText
    }
  }
}

enum DiagnosticTranslationFailureReason: String, Codable, Sendable {
  case translationServiceNotConfigured
  case inputExceedsTranslationLimit
  case requestTimedOut
  case networkUnavailable
  case requestRejected
  case invalidHTTPResponse
  case authenticationFailed
  case quotaExceeded
  case rateLimited
  case serviceUnavailable
  case responseJSONCouldNotBeDecoded
  case responseInputKindMissing
  case responseRequiredFieldsMissing
  case responseInputKindUnexpected
  case responseSourceTextMismatch
  case responseCanonicalFormIsNotEnglish
  case responseExampleSentenceIsNotEnglish
  case exampleSentenceDoesNotMatchSelectionContext
  case responseMeaningIsNotChinese
  case responseSentenceTranslationIsNotChinese
  case longTextSourceTextMismatch
  case longTextTranslationIsNotChinese
}

struct DiagnosticTranslationDetails: Sendable {
  let provider: String
  let model: String
  let requestKind: DiagnosticTranslationRequestKind
  let failureReason: DiagnosticTranslationFailureReason?
  let missingResponseFields: [String]?
  let httpStatusCode: Int?

  init(
    provider: String,
    model: String,
    requestKind: DiagnosticTranslationRequestKind,
    failureReason: DiagnosticTranslationFailureReason? = nil,
    missingResponseFields: [String]? = nil,
    httpStatusCode: Int? = nil
  ) {
    self.provider = provider
    self.model = model
    self.requestKind = requestKind
    self.failureReason = failureReason
    self.missingResponseFields = missingResponseFields
    self.httpStatusCode = httpStatusCode
  }
}

struct DiagnosticEvent: Codable, Equatable, Sendable {
  let appVersion: String
  let systemVersion: String
  let sourceApplicationIdentifier: String?
  let stage: DiagnosticStage
  let errorType: DiagnosticErrorType?
  let durationMilliseconds: Int?
  let provider: String?
  let model: String?
  let requestKind: DiagnosticTranslationRequestKind?
  let failureReason: DiagnosticTranslationFailureReason?
  let missingResponseFields: [String]?
  let httpStatusCode: Int?
}

struct DiagnosticArchive: Codable, Equatable, Sendable {
  static let currentFormatVersion = 2

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
  func recordTranslation(
    stage: DiagnosticStage,
    sourceApplicationIdentifier: String?,
    errorType: DiagnosticErrorType?,
    durationMilliseconds: Int?,
    details: DiagnosticTranslationDetails
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
    DiagnosticArchive(
      formatVersion: DiagnosticArchive.currentFormatVersion,
      exportedAt: exportedAt,
      events: []
    )
  }

  func recordTranslation(
    stage: DiagnosticStage,
    sourceApplicationIdentifier: String?,
    errorType: DiagnosticErrorType?,
    durationMilliseconds: Int?,
    details _: DiagnosticTranslationDetails
  ) {
    record(
      stage: stage,
      sourceApplicationIdentifier: sourceApplicationIdentifier,
      errorType: errorType,
      durationMilliseconds: durationMilliseconds
    )
  }
}

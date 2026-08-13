enum TranslationRequestKind: Codable, Equatable, Hashable, Sendable {
  case wordOrPhrase
  case contextualSelection
  case longText
}

struct TranslationRequest: Codable, Equatable, Hashable, Sendable {
  let sourceText: String
  let context: String?
  let kind: TranslationRequestKind
  let targetSentence: String?
  let selectionWordContext: SelectionWordContext?
  let chineseWritingSystem: ChineseWritingSystem

  init(
    sourceText: String,
    context: String? = nil,
    kind: TranslationRequestKind = .wordOrPhrase,
    targetSentence: String? = nil,
    selectionWordContext: SelectionWordContext? = nil,
    chineseWritingSystem: ChineseWritingSystem = .simplified
  ) {
    self.sourceText = sourceText
    self.context = context
    self.kind = kind
    self.targetSentence = targetSentence
    self.selectionWordContext = selectionWordContext
    self.chineseWritingSystem = chineseWritingSystem
  }

  var promptContent: String {
    guard let context, !context.isEmpty else {
      return sourceText
    }

    var content = """
      Target text:
      \(sourceText)

      Context:
      \(context)
      """
    if kind == .contextualSelection {
      if let targetSentence {
        content += """


          The locally detected sentence below is only a potentially incomplete hint:
          \(targetSentence)
          """
      }

      content += """


        Extract the complete original sentence containing the selected occurrence from Context.
        Formatting boundaries such as italics, links, bold text, or inline elements are not
        sentence boundaries. Rejoin text across those boundaries when it belongs to the same
        sentence. Copy that complete sentence exactly as example_sentence, without the Context
        labels, and translate it as sentence_translation.
        """
    }
    return content
  }
}

struct TranslationResult: Codable, Equatable, Sendable {
  let sourceText: String
  let canonicalForm: String
  let pronunciation: String
  let partOfSpeech: String
  let contextualMeaning: String
  let exampleSentence: String
  let sentenceTranslation: String
}

struct LongTextTranslationResult: Equatable, Sendable {
  let sourceText: String
  let translatedText: String
}

enum TranslationError: Error, Equatable, Sendable {
  case notConfigured
  case inputTooLong
  case timedOut
  case networkUnavailable
  case invalidResponse(
    TranslationResponseValidationFailure = .malformedPayload,
    diagnosticReason: DiagnosticTranslationFailureReason? = nil,
    missingResponseFields: [String]? = nil,
    httpStatusCode: Int? = nil
  )
  case invalidRequest
  case authenticationFailed
  case quotaExceeded
  case rateLimited
  case serviceUnavailable
  case httpFailure(TranslationHTTPFailure, statusCode: Int)

  var userFacingMessageKey: String {
    switch self {
    case .notConfigured:
      "尚未配置此翻译服务的 API Key。请到“设置 > 翻译服务”完成配置。"
    case .inputTooLong:
      "内容超过约 12000 字符或 token 预算，请缩短后重试。"
    case .timedOut:
      "翻译请求超时。请检查网络后重试。"
    case .networkUnavailable:
      "无法连接到翻译服务。请检查网络、代理或服务地址。"
    case .invalidResponse(let failure, _, _, _):
      failure.userFacingMessageKey
    case .invalidRequest:
      TranslationHTTPFailure.invalidRequest.userFacingMessageKey
    case .authenticationFailed:
      TranslationHTTPFailure.authenticationFailed.userFacingMessageKey
    case .quotaExceeded:
      TranslationHTTPFailure.quotaExceeded.userFacingMessageKey
    case .rateLimited:
      TranslationHTTPFailure.rateLimited.userFacingMessageKey
    case .serviceUnavailable:
      TranslationHTTPFailure.serviceUnavailable.userFacingMessageKey
    case .httpFailure(let failure, _):
      failure.userFacingMessageKey
    }
  }

  var diagnosticFailureReason: DiagnosticTranslationFailureReason? {
    switch self {
    case .notConfigured:
      return .translationServiceNotConfigured
    case .inputTooLong:
      return .inputExceedsTranslationLimit
    case .timedOut:
      return .requestTimedOut
    case .networkUnavailable:
      return .networkUnavailable
    case .invalidResponse(let failure, let reason, _, _):
      return reason ?? failure.defaultDiagnosticReason
    case .invalidRequest:
      return .requestRejected
    case .authenticationFailed:
      return .authenticationFailed
    case .quotaExceeded:
      return .quotaExceeded
    case .rateLimited:
      return .rateLimited
    case .serviceUnavailable:
      return .serviceUnavailable
    case .httpFailure(let failure, _):
      return failure.diagnosticFailureReason
    }
  }

  var diagnosticMissingResponseFields: [String]? {
    guard case .invalidResponse(_, _, let fields, _) = self else {
      return nil
    }
    return fields
  }

  var httpStatusCode: Int? {
    switch self {
    case .invalidResponse(_, _, _, let statusCode):
      return statusCode
    case .httpFailure(_, let statusCode):
      return statusCode
    default:
      return nil
    }
  }
}

enum TranslationHTTPFailure: Equatable, Sendable {
  case invalidRequest
  case authenticationFailed
  case quotaExceeded
  case rateLimited
  case timedOut
  case inputTooLong
  case serviceUnavailable

  var userFacingMessageKey: String {
    switch self {
    case .invalidRequest:
      "翻译服务拒绝了请求。请检查服务地址、模型名称和输入内容。"
    case .authenticationFailed:
      "API Key 无效、已失效，或没有使用当前模型的权限。请在设置中更新 Key 或模型。"
    case .quotaExceeded:
      "API Key 的余额或可用额度不足。请在服务商后台充值，或更换 API Key。"
    case .rateLimited:
      "翻译请求过于频繁，服务暂时限流。请稍候再试。"
    case .timedOut:
      "翻译请求超时。请检查网络后重试。"
    case .inputTooLong:
      "内容超过约 12000 字符或 token 预算，请缩短后重试。"
    case .serviceUnavailable:
      "翻译服务暂时不可用。请稍后重试。"
    }
  }

  var diagnosticFailureReason: DiagnosticTranslationFailureReason {
    switch self {
    case .invalidRequest:
      .requestRejected
    case .authenticationFailed:
      .authenticationFailed
    case .quotaExceeded:
      .quotaExceeded
    case .rateLimited:
      .rateLimited
    case .timedOut:
      .requestTimedOut
    case .inputTooLong:
      .inputExceedsTranslationLimit
    case .serviceUnavailable:
      .serviceUnavailable
    }
  }

  var diagnosticErrorType: DiagnosticErrorType {
    switch self {
    case .invalidRequest:
      .requestRejected
    case .authenticationFailed:
      .authentication
    case .quotaExceeded:
      .quota
    case .rateLimited:
      .rateLimited
    case .timedOut:
      .timeout
    case .inputTooLong:
      .configuration
    case .serviceUnavailable:
      .network
    }
  }
}

enum TranslationResponseValidationFailure: Equatable, Sendable {
  case malformedPayload
  case unexpectedInputKind
  case missingRequiredContent
  case invalidEnglishContent
  case invalidChineseContent

  var userFacingMessageKey: String {
    switch self {
    case .malformedPayload:
      "翻译服务返回的数据无法解析。请重试。"
    case .unexpectedInputKind:
      "翻译服务返回了错误的内容类型。请重试。"
    case .missingRequiredContent:
      "翻译服务返回的学习内容不完整。请重试。"
    case .invalidEnglishContent:
      "翻译服务返回的英文词条或例句无效。请重试。"
    case .invalidChineseContent:
      "翻译服务返回的中文释义或译文无效。请重试。"
    }
  }

  var defaultDiagnosticReason: DiagnosticTranslationFailureReason {
    switch self {
    case .malformedPayload:
      .responseJSONCouldNotBeDecoded
    case .unexpectedInputKind:
      .responseInputKindUnexpected
    case .missingRequiredContent:
      .responseRequiredFieldsMissing
    case .invalidEnglishContent:
      .responseExampleSentenceIsNotEnglish
    case .invalidChineseContent:
      .responseMeaningIsNotChinese
    }
  }
}

@MainActor
protocol TranslationProviding {
  func translate(_ request: TranslationRequest) async throws -> TranslationResult
  func translateLongText(_ sourceText: String) async throws -> LongTextTranslationResult
  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult
}

extension TranslationProviding {
  func translateLongText(_ sourceText: String) async throws -> LongTextTranslationResult {
    try await translateLongText(sourceText, chineseWritingSystem: .simplified)
  }

  func translateLongText(
    _ sourceText: String,
    chineseWritingSystem: ChineseWritingSystem
  ) async throws -> LongTextTranslationResult {
    throw TranslationError.invalidResponse(.malformedPayload)
  }
}
